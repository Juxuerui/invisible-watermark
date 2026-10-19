import Foundation
import CryptoKit

/// In-app issuing, used only by the ActivationTool build.
///
/// The private key is supplied by the operator at runtime (paste or import file)
/// and kept in memory; it is never compiled into the app. That way the tool can
/// sign licences while the shipped binary still contains only the public key.
public enum LicenseIssuer {

    public struct Issued {
        public let code: String
        public let expire: UInt32
    }

    public enum Error: LocalizedError {
        case invalidDeviceCode
        case invalidPrivateKey
        case notP256
        case signingFailed

        public var errorDescription: String? {
            switch self {
            case .invalidDeviceCode: return "设备码无效：应为 13 个 Base32 字符（分组后 5-5-3）"
            case .invalidPrivateKey: return "私钥无法解析：请粘贴 PEM（P-256 / prime256v1）"
            case .notP256: return "私钥类型不对：需要 P-256（secp256r1）曲线"
            case .signingFailed: return "签名失败"
            }
        }
    }

    static let permanent: UInt32 = 0xFFFFFFFF

    // MARK: - Device code parsing

    /// Parse a grouped device code such as `4CNAL-MCNWJ-SYE` into 8 raw bytes.
    public static func fingerprint(fromDeviceCode code: String) -> [UInt8]? {
        let cleaned = code
            .uppercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        let bytes = Base32.decode(cleaned)
        return bytes.count == 8 ? bytes : nil
    }

    // MARK: - Key import

    public static func privateKey(fromPEM pem: String) throws -> P256.Signing.PrivateKey {
        let trimmed = pem.trimmingCharacters(in: .whitespacesAndNewlines)
        // PKCS#8: BEGIN PRIVATE KEY
        if let der = pemBody(trimmed, header: "BEGIN PRIVATE KEY", footer: "END PRIVATE KEY"),
           let key = try? P256.Signing.PrivateKey(derRepresentation: der) {
            return key
        }
        // SEC1: BEGIN EC PRIVATE KEY — CryptoKit has no SEC1 initializer, so the
        // operator must supply the PKCS#8 export (openssl pkcs8 -topk8 -nocrypt).
        if trimmed.contains("BEGIN EC PRIVATE KEY") {
            throw Error.invalidPrivateKey
        }
        throw Error.invalidPrivateKey
    }

    static func pemBody(_ pem: String, header: String, footer: String) -> Data? {
        // Parse line by line: matching substrings with range(of:) can hit the
        // dashes inside the markers themselves.
        var collecting = false
        var body = ""
        for rawLine in pem.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("-----BEGIN") {
                collecting = line.contains(header)
                continue
            }
            if line.hasPrefix("-----END") {
                if collecting { break }
                continue
            }
            if collecting {
                body += line
            }
        }
        guard !body.isEmpty else { return nil }
        return Data(base64Encoded: body)
    }

    // MARK: - Issuing

    public static func issue(deviceCode: String,
                             expire: UInt32,
                             privateKey: P256.Signing.PrivateKey) throws -> Issued {
        guard let fingerprint = fingerprint(fromDeviceCode: deviceCode) else {
            throw Error.invalidDeviceCode
        }
        var payload = [UInt8]()
        payload.append(1)
        payload.append(UInt8((expire >> 24) & 0xFF))
        payload.append(UInt8((expire >> 16) & 0xFF))
        payload.append(UInt8((expire >> 8) & 0xFF))
        payload.append(UInt8(expire & 0xFF))
        payload.append(contentsOf: fingerprint)

        let data = Data(payload)
        guard let signature = try? privateKey.signature(for: data) else {
            throw Error.signingFailed
        }
        let signatureBytes = Array(signature.derRepresentation)
        let code = "\(Base32.encode(payload)).\(Base32.encode(signatureBytes))"
        return Issued(code: code, expire: expire)
    }

    /// Convert an expiry policy into the Unix seconds stored in the payload.
    public static func expireSeconds(days: Int?) -> UInt32 {
        guard let days else { return permanent }
        if days < 0 { return permanent }
        let date = Date().addingTimeInterval(TimeInterval(days) * 86_400)
        return UInt32(date.timeIntervalSince1970)
    }

    /// Public key fingerprint so the operator can confirm the app and issuer
    /// script are using the same key pair.
    public static func publicKeyFingerprint() -> String {
        guard let data = Data(base64Encoded: License.publicKeyBase64) else { return "" }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
