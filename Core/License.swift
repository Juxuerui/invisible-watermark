import Foundation
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

/// Device bound license verification.
///
/// License text format: `<base32(payload)>.<base32(signature)>`
///   payload   = version(1) | expireSec(4, big endian) | deviceFingerprint(8)
///   signature = ECDSA P-256 / SHA-256 over the 13 payload bytes
///
/// The public key is the same one the Android build embeds, so licence codes
/// generated for the Android app verify here as long as the device id matches.
/// iOS cannot reproduce Android's `android_id`, therefore a fresh device code is
/// derived from the vendor identifier. Issue licenses against the code shown by
/// this app.
public enum License {

    public struct Result {
        public let ok: Bool
        public let reason: String
        public let expireSec: UInt32
        public var isPermanent: Bool { expireSec == 0xFFFFFFFF }
    }

    /// Tencent app's embedded P-256 public key (X9.62 uncompressed point).
    static let publicKeyBase64 = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEQiMooch7T9LOJAQwm1xB1MRwBTC+B3rTtacXCu0GVnHErkJHAlNTH+P4dSXh93U/6lbwk29XSti+pX1DzujOIA=="

    // MARK: - Device identity

    /// Stable per-install identifier. Stored in UserDefaults after first launch so
    /// the licence survives reinstallation only when the keychain item survives.
    public static func deviceFingerprint() -> [UInt8] {
        let id = deviceIdentifier()
        let digest = SHA256.hash(data: Data(id.utf8))
        return Array(digest.prefix(8))
    }

    static func deviceIdentifier() -> String {
        let key = "watermark.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        #if canImport(UIKit)
        let candidate = UIDevice.current.identifierForVendor?.uuidString ?? "ios-unknown-device"
        #else
        let candidate = "mac-\(ProcessInfo.processInfo.hostName)"
        #endif
        UserDefaults.standard.set(candidate, forKey: key)
        return candidate
    }

    public static func deviceCode() -> String {
        group(Base32.encode(deviceFingerprint()))
    }

    static func group(_ value: String) -> String {
        var out = ""
        for (index, char) in value.enumerated() {
            if index > 0, index % 5 == 0 { out.append("-") }
            out.append(char)
        }
        return out
    }

    // MARK: - Verification

    public static func verify(_ raw: String?) -> Result {
        guard let raw else { return Result(ok: false, reason: "未输入授权码", expireSec: 0) }
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")

        guard let dot = cleaned.firstIndex(of: ".") else {
            return Result(ok: false, reason: "授权码格式错误（应为 设备段.签名段）", expireSec: 0)
        }
        let payloadPart = String(cleaned[cleaned.startIndex..<dot])
        let signaturePart = String(cleaned[cleaned.index(after: dot)...])
        guard !payloadPart.isEmpty, !signaturePart.isEmpty else {
            return Result(ok: false, reason: "授权码格式错误（应为 设备段.签名段）", expireSec: 0)
        }

        let payload = Base32.decode(payloadPart)
        let signature = Base32.decode(signaturePart)
        guard payload.count == 13 else {
            return Result(ok: false, reason: "授权码内容长度错误", expireSec: 0)
        }
        guard payload[0] == 1 else {
            return Result(ok: false, reason: "授权码版本不支持", expireSec: 0)
        }

        let expire = (UInt32(payload[1]) << 24) | (UInt32(payload[2]) << 16) |
                     (UInt32(payload[3]) << 8) | UInt32(payload[4])
        let boundFingerprint = Array(payload[5..<13])

        guard verifySignature(payload: Array(payload[0..<13]),
                              signature: signature,
                              publicKeyBase64: publicKeyBase64) else {
            return Result(ok: false, reason: "授权码无效（签名校验失败，可能被篡改或复制到其他设备）", expireSec: 0)
        }

        let localFingerprint = deviceFingerprint()
        guard constantTimeEquals(boundFingerprint, localFingerprint) else {
            let bound = group(Base32.encode(boundFingerprint))
            let local = group(Base32.encode(localFingerprint))
            return Result(ok: false,
                          reason: "设备不匹配：该授权码绑定的设备码是 \(bound)，而你本机设备码是 \(local)。请在授权码生成器把设备码改成本机这个再重新生成。",
                          expireSec: 0)
        }

        let now = UInt32(Date().timeIntervalSince1970)
        if expire != 0xFFFFFFFF, now > expire {
            return Result(ok: false, reason: "授权已到期", expireSec: expire)
        }
        return Result(ok: true, reason: "", expireSec: expire)
    }

    static func verifySignature(payload: [UInt8],
                                signature: [UInt8],
                                publicKeyBase64: String) -> Bool {
        guard let keyData = Data(base64Encoded: publicKeyBase64),
              let key = try? P256.Signing.PublicKey(derRepresentation: keyData) else {
            return false
        }
        // Accept both DER and raw (r||s) signatures; generators differ.
        if let sig = try? P256.Signing.ECDSASignature(derRepresentation: Data(signature)),
           key.isValidSignature(sig, for: Data(payload)) {
            return true
        }
        if let sig = try? P256.Signing.ECDSASignature(rawRepresentation: Data(signature)),
           key.isValidSignature(sig, for: Data(payload)) {
            return true
        }
        return false
    }

    static func constantTimeEquals(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }

    public static func expireText(_ expire: UInt32) -> String {
        if expire == 0xFFFFFFFF { return "永久" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(expire)))
    }
}

/// RFC 4648 base32 without padding, matching the Android implementation.
public enum Base32 {
    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    public static func decode(_ input: String) -> [UInt8] {
        var out: [UInt8] = []
        var buffer = 0
        var bits = 0
        for char in input.uppercased() {
            guard let index = alphabet.firstIndex(of: char) else { continue }
            buffer = (buffer << 5) | index
            bits += 5
            if bits >= 8 {
                out.append(UInt8((buffer >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        return out
    }

    public static func encode(_ bytes: [UInt8]) -> String {
        var out = ""
        var buffer = 0
        var bits = 0
        for byte in bytes {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                out.append(alphabet[(buffer >> (bits - 5)) & 31])
                bits -= 5
            }
        }
        if bits > 0 {
            out.append(alphabet[(buffer << (5 - bits)) & 31])
        }
        return out
    }
}
