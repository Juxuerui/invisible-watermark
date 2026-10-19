import Foundation
import CFNetwork

/// Blocking SMTP client built on CFStream so that both implicit TLS (465) and
/// STARTTLS (587) can be supported without third party dependencies.
public final class SMTPClient {

    public enum Error: LocalizedError {
        case connectionFailed(String)
        case unexpectedResponse(String)
        case tlsFailed(String)
        case authFailed(String)

        public var errorDescription: String? {
            switch self {
            case .connectionFailed(let m): return "连接失败：\(m)"
            case .unexpectedResponse(let m): return "服务器响应异常：\(m)"
            case .tlsFailed(let m): return "TLS 失败：\(m)"
            case .authFailed(let m): return "认证失败：\(m)"
            }
        }
    }

    let host: String
    let port: Int
    let security: EmailUtil.Security

    public init(host: String, port: Int, security: EmailUtil.Security) {
        self.host = host
        self.port = port
        self.security = security
    }

    public func send(from: String,
                     to: String,
                     user: String,
                     password: String,
                     message: Data) throws {
        let transport = try StreamTransport(host: host,
                                            port: port,
                                            implicitTLS: security == .implicitTLS)
        defer { transport.close() }

        try expect(transport.readReply(), code: 220)

        var capabilities = try command(transport, "EHLO watermark.local", expect: 250)

        if case .startTLS = security {
            try command(transport, "STARTTLS", expect: 220)
            try transport.upgradeToTLS()
            capabilities = try command(transport, "EHLO watermark.local", expect: 250)
        }

        let upper = capabilities.uppercased()
        if upper.contains("AUTH") && upper.contains("PLAIN") {
            let token = Data("\u{0}\(user)\u{0}\(password)".utf8).base64EncodedString()
            try command(transport, "AUTH PLAIN \(token)", expect: 235)
        } else {
            try command(transport, "AUTH LOGIN", expect: 334)
            try command(transport, Data(user.utf8).base64EncodedString(), expect: 334)
            try command(transport, Data(password.utf8).base64EncodedString(), expect: 235)
        }

        try command(transport, "MAIL FROM:<\(from)>", expect: 250)
        try command(transport, "RCPT TO:<\(to)>", expect: 250)
        try command(transport, "DATA", expect: 354)
        try transport.write(message)
        try transport.write(Data("\r\n.\r\n".utf8))
        try expect(transport.readReply(), code: 250)
        _ = try? command(transport, "QUIT", expect: 221)
    }

    private func command(_ transport: StreamTransport, _ text: String, expect code: Int) throws -> String {
        try transport.write(Data((text + "\r\n").utf8))
        let reply = try transport.readReply()
        try expect(reply, code: code)
        return reply
    }

    private func expect(_ reply: String, code: Int) throws {
        guard reply.hasPrefix("\(code)") else {
            let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            if reply.hasPrefix("535") || reply.hasPrefix("530") {
                throw Error.authFailed(trimmed)
            }
            throw Error.unexpectedResponse(trimmed)
        }
    }
}

/// CFStream based socket with blocking reads and optional TLS upgrade.
final class StreamTransport {
    private var readStream: InputStream
    private var writeStream: OutputStream
    private let host: String
    private var buffer = Data()
    private let ioQueue = DispatchQueue(label: "smtp.stream")
    private var opened = false

    init(host: String, port: Int, implicitTLS: Bool) throws {
        self.host = host
        var read: Unmanaged<CFReadStream>?
        var write: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(nil, host as CFString, UInt32(port), &read, &write)
        guard let cfRead = read?.takeRetainedValue(),
              let cfWrite = write?.takeRetainedValue() else {
            throw SMTPClient.Error.connectionFailed("无法创建套接字")
        }
        readStream = cfRead as InputStream
        writeStream = cfWrite as OutputStream

        if implicitTLS {
            try applyTLS()
        }

        readStream.open()
        writeStream.open()

        // Wait for the socket to become usable.
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if readStream.streamStatus == .open, writeStream.streamStatus == .open {
                opened = true
                return
            }
            if readStream.streamStatus == .error || writeStream.streamStatus == .error {
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if !opened {
            throw SMTPClient.Error.connectionFailed(readStream.streamError?.localizedDescription ?? "连接超时")
        }
    }

    func upgradeToTLS() throws {
        try applyTLS()
    }

    private func applyTLS() throws {
        let settings: [String: Any] = [
            kCFStreamSSLPeerName as String: host,
            kCFStreamSSLLevel as String: kCFStreamSocketSecurityLevelNegotiatedSSL as String
        ]
        let readOK = CFReadStreamSetProperty(readStream as CFReadStream,
                                             CFStreamPropertyKey(kCFStreamPropertySSLSettings),
                                             settings as CFDictionary)
        let writeOK = CFWriteStreamSetProperty(writeStream as CFWriteStream,
                                               CFStreamPropertyKey(kCFStreamPropertySSLSettings),
                                               settings as CFDictionary)
        guard readOK, writeOK else {
            throw SMTPClient.Error.tlsFailed("无法启用 TLS")
        }
    }

    func write(_ data: Data) throws {
        var remaining = [UInt8](data)
        var offset = 0
        while offset < remaining.count {
            let written = writeStream.write(remaining, maxLength: remaining.count - offset)
            if written < 0 {
                throw SMTPClient.Error.connectionFailed(writeStream.streamError?.localizedDescription ?? "写入失败")
            }
            offset += written
            if written == 0 { break }
        }
        if offset < remaining.count {
            throw SMTPClient.Error.connectionFailed("写入不完整")
        }
    }

    func readReply() throws -> String {
        while true {
            if let text = String(data: buffer, encoding: .utf8) {
                let lines = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }
                if let last = lines.last, last.count >= 4 {
                    let code = last.prefix(3)
                    let separator = last[last.index(last.startIndex, offsetBy: 3)]
                    if code.allSatisfy(\.isNumber), separator == " " {
                        buffer.removeAll()
                        return text
                    }
                }
            }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let count = readStream.read(&chunk, maxLength: chunk.count)
            if count < 0 {
                throw SMTPClient.Error.connectionFailed(readStream.streamError?.localizedDescription ?? "读取失败")
            }
            if count == 0 {
                if buffer.isEmpty {
                    throw SMTPClient.Error.connectionFailed("连接已断开")
                }
                let text = String(data: buffer, encoding: .utf8) ?? ""
                buffer.removeAll()
                return text
            }
            buffer.append(contentsOf: chunk[0..<count])
        }
    }

    func close() {
        readStream.close()
        writeStream.close()
    }
}
