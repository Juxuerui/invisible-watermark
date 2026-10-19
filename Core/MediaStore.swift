import Foundation

/// Photos app helper, image file naming and zip handling ported from ImageUtil.
public enum MediaStore {

    public static let imageExtensions = ["jpg", "jpeg", "png", "bmp", "webp", "psd"]

    public static func isImageFile(_ name: String) -> Bool {
        let lower = name.lowercased()
        return imageExtensions.contains { lower.hasSuffix("." + $0) }
    }

    public static func isZipFile(_ name: String) -> Bool {
        name.lowercased().hasSuffix(".zip")
    }

    public static func generateFileName(qq: String, index: Int, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale.current
        return "wm_\(qq)_\(formatter.string(from: date))_\(index).png"
    }

    /// Extract the QQ number back out of `wm_<qq>_<date>_<index>.<ext>`.
    public static func extractQQFromFileName(_ name: String) -> String? {
        guard let wmRange = name.range(of: "wm_") else { return nil }
        let rest = name[wmRange.upperBound...]
        guard let underscore = rest.firstIndex(of: "_") else { return nil }
        let candidate = String(rest[rest.startIndex..<underscore])
        guard candidate.count >= 5, candidate.count <= 11, candidate.allSatisfy(\.isNumber) else {
            return nil
        }
        return candidate
    }

    /// Extract the QQ number out of `<prefix>QQ<number>.zip`.
    public static func extractQQFromZipName(_ name: String) -> String? {
        guard let range = name.range(of: "QQ") else { return nil }
        guard let zipRange = name.range(of: ".zip", options: .backwards) else { return nil }
        guard zipRange.lowerBound > range.upperBound else { return nil }
        let value = String(name[range.upperBound..<zipRange.lowerBound])
        return value.isEmpty ? nil : value
    }

    public static func zipName(forQQ qq: String) -> String {
        "水印图片_QQ\(qq).zip"
    }

    // MARK: - Directories

    public static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    public static func ensure(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func outputDirectory() -> URL {
        (try? ensure(documentsDirectory.appendingPathComponent("watermarked", isDirectory: true)))
            ?? documentsDirectory
    }

    public static func zipDirectory() -> URL {
        (try? ensure(documentsDirectory.appendingPathComponent("zips", isDirectory: true)))
            ?? documentsDirectory
    }

    public static func tempDirectory() -> URL {
        (try? ensure(FileManager.default.temporaryDirectory.appendingPathComponent("watermark-temp", isDirectory: true)))
            ?? FileManager.default.temporaryDirectory
    }

    // MARK: - Writing

    public enum Format {
        case png, jpeg, webp, psd

        static func from(fileName: String) -> Format {
            let lower = fileName.lowercased()
            if lower.hasSuffix(".psd") { return .psd }
            if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return .jpeg }
            if lower.hasSuffix(".webp") { return .webp }
            return .png
        }
    }

    @discardableResult
    public static func save(_ image: RGBAImage, directory: URL, fileName: String) -> URL? {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent(fileName)
            switch Format.from(fileName: fileName) {
            case .psd:
                try PSDEncoder.write(image, to: target)
            case .png:
                guard let data = Encoder.pngData(image) else { return nil }
                try data.write(to: target)
            case .jpeg:
                guard let data = Encoder.jpegData(image, quality: 1.0) else { return nil }
                try data.write(to: target)
            case .webp:
                // WebP encoding needs a third party codec; fall back to PNG bytes
                // instead of silently writing a mislabelled file.
                guard let data = Encoder.pngData(image) else { return nil }
                try data.write(to: target)
            }
            return target
        } catch {
            return nil
        }
    }
}
