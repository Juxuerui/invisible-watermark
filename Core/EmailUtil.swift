import Foundation

/// SMTP client with STARTTLS / implicit TLS and one MIME attachment.
/// Mirrors EmailUtil: defaults to smtp.qq.com:465, port 587 switches to STARTTLS.
public final class EmailUtil {

    public struct Config: Codable, Equatable {
        public var smtpHost: String
        public var smtpPort: String
        public var account: String
        public var password: String

        public static let `default` = Config(smtpHost: "smtp.qq.com", smtpPort: "465", account: "", password: "")

        public var isValid: Bool {
            !account.trimmingCharacters(in: .whitespaces).isEmpty &&
            !password.trimmingCharacters(in: .whitespaces).isEmpty
        }

        public var port: Int { Int(smtpPort) ?? 465 }
    }

    public enum SendError: LocalizedError {
        case notConfigured
        case connectionFailed(String)
        case commandFailed(String)
        case attachmentMissing

        public var errorDescription: String? {
            switch self {
            case .notConfigured: return "邮箱配置不完整"
            case .connectionFailed(let message): return "连接失败：\(message)"
            case .commandFailed(let message): return "发送失败：\(message)"
            case .attachmentMissing: return "附件不存在"
            }
        }
    }

    // MARK: - Persistence

    static let storageKey = "email.config.v1"

    public static func loadConfig() -> Config {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return .default
        }
        return config
    }

    public static func saveConfig(_ config: Config) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    public static func qqToEmail(_ qq: String) -> String {
        "\(qq)@qq.com"
    }

    // MARK: - Sending

    public enum Security {
        case implicitTLS   // port 465
        case startTLS      // port 587
        case plaintext     // anything else, matches original behaviour
    }

    public static func security(for port: Int) -> Security {
        switch port {
        case 465: return .implicitTLS
        case 587: return .startTLS
        default: return .plaintext
        }
    }

    /// Build the raw RFC 5322 message with a single attachment.
    public static func buildMessage(from account: String,
                                    to recipient: String,
                                    subject: String,
                                    htmlBody: String,
                                    attachment: URL?) throws -> Data {
        guard let attachment, FileManager.default.fileExists(atPath: attachment.path) else {
            throw SendError.attachmentMissing
        }
        let boundary = "----WatermarkBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let attachmentData = try Data(contentsOf: attachment)
        let attachmentName = attachment.lastPathComponent

        var message = ""
        message += "From: \(account)\r\n"
        message += "To: \(recipient)\r\n"
        message += "Subject: =?UTF-8?B?\(Data(subject.utf8).base64EncodedString())?=\r\n"
        message += "MIME-Version: 1.0\r\n"
        message += "Content-Type: multipart/mixed; boundary=\"\(boundary)\"\r\n"
        message += "\r\n"
        message += "--\(boundary)\r\n"
        message += "Content-Type: text/html; charset=UTF-8\r\n"
        message += "Content-Transfer-Encoding: base64\r\n\r\n"
        message += Data(htmlBody.utf8).base64EncodedString(options: .lineLength64Characters)
        message += "\r\n--\(boundary)\r\n"
        message += "Content-Type: application/octet-stream; name=\"=?UTF-8?B?\(Data(attachmentName.utf8).base64EncodedString())?=\"\r\n"
        message += "Content-Disposition: attachment; filename=\"=?UTF-8?B?\(Data(attachmentName.utf8).base64EncodedString())?=\"\r\n"
        message += "Content-Transfer-Encoding: base64\r\n\r\n"
        message += attachmentData.base64EncodedString(options: .lineLength76Characters)
        message += "\r\n--\(boundary)--\r\n"

        return Data(message.utf8)
    }

    public static func send(config: Config,
                            to recipient: String,
                            subject: String,
                            htmlBody: String,
                            attachment: URL) throws {
        guard config.isValid else { throw SendError.notConfigured }
        let message = try buildMessage(from: config.account,
                                       to: recipient,
                                       subject: subject,
                                       htmlBody: htmlBody,
                                       attachment: attachment)
        let client = SMTPClient(host: config.smtpHost,
                                port: config.port,
                                security: security(for: config.port))
        try client.send(from: config.account,
                        to: recipient,
                        user: config.account,
                        password: config.password,
                        message: message)
    }
}
