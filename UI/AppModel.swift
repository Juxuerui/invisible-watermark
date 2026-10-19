import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class AppModel: ObservableObject {

    // MARK: - License

    @Published var licenseOK: Bool {
        didSet { UserDefaults.standard.set(licenseOK, forKey: Self.licenseKey) }
    }
    @Published var licenseReason: String = ""
    @Published var licenseCodeInput: String = ""

    static let licenseKey = "watermark.license.ok"

    // MARK: - Embed screen

    @Published var embedImages: [PickedImage] = []
    @Published var qqInput: String = ""
    @Published var robustMode: Bool = false
    @Published var embedProgress: Double = 0
    @Published var embedStatus: String = ""
    @Published var embedRunning: Bool = false
    @Published var watermarkedFiles: [URL] = []
    @Published var generatedZips: [URL] = []
    @Published var embedResultText: String = ""
    @Published var showImagePicker = false

    // MARK: - Detect screen

    @Published var detectResults: [DetectItem] = []
    @Published var detectProgress: Double = 0
    @Published var detectStatus: String = ""
    @Published var detectRunning: Bool = false
    @Published var showDetectPicker = false
    @Published var showZipPicker = false

    // MARK: - Email

    @Published var emailConfig: EmailUtil.Config = EmailUtil.loadConfig()
    @Published var emailStatus: String = ""
    @Published var showEmailConfig = false

    // MARK: - Shared

    @Published var toast: String?

    private let queue = DispatchQueue(label: "watermark.work", qos: .userInitiated)

    public init() {
        licenseOK = UserDefaults.standard.bool(forKey: Self.licenseKey)
    }

    // MARK: - License

    func checkLicense() {
        let raw = UserDefaults.standard.string(forKey: "watermark.license.code")
        guard let raw, !raw.isEmpty else {
            licenseOK = false
            licenseReason = ""
            return
        }
        let result = License.verify(raw)
        licenseOK = result.ok
        licenseReason = result.reason
    }

    func activate() {
        let result = License.verify(licenseCodeInput)
        if result.ok {
            UserDefaults.standard.set(licenseCodeInput, forKey: "watermark.license.code")
            licenseOK = true
            licenseReason = ""
        } else {
            licenseOK = false
            licenseReason = result.reason
        }
    }

    func deactivate() {
        UserDefaults.standard.removeObject(forKey: "watermark.license.code")
        licenseOK = false
        licenseReason = ""
    }

    var licenseExpireText: String {
        guard let raw = UserDefaults.standard.string(forKey: "watermark.license.code") else { return "" }
        let result = License.verify(raw)
        return License.expireText(result.expireSec)
    }

    // MARK: - Parsing helpers

    /// Split QQ input on newlines, commas (half and full width), semicolons and
    /// whitespace, keeping only 5-11 digit entries, exactly like parseQQNumbers.
    public static func parseQQNumbers(_ text: String) -> [String] {
        let separators = CharacterSet(charactersIn: "\n,，;； \t\r")
        return text.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { value in
                guard value.count >= 5, value.count <= 11 else { return false }
                return value.allSatisfy(\.isNumber)
            }
    }

    var parsedQQ: [String] { Self.parseQQNumbers(qqInput) }

    // MARK: - Embedding

    func startEmbedding() {
        let qqList = parsedQQ
        guard !embedImages.isEmpty else {
            toast = "请先选择图片"
            return
        }
        guard !qqList.isEmpty else {
            toast = "请先输入QQ号"
            return
        }

        embedRunning = true
        embedProgress = 0
        watermarkedFiles = []
        generatedZips = []
        embedResultText = ""
        let total = embedImages.count * qqList.count
        let images = embedImages
        let robust = robustMode
        embedStatus = "正在打标: 0/\(total)"

        queue.async {
            let outputDir = MediaStore.outputDirectory()
            var produced: [URL] = []
            var index = 0
            for (imageIndex, item) in images.enumerated() {
                guard let source = Encoder.loadAndDownsample(url: item.url) else {
                    index += qqList.count
                    continue
                }
                for (qqIndex, qq) in qqList.enumerated() {
                    let flat = imageIndex * qqList.count + qqIndex
                    let result: RGBAImage?
                    if robust {
                        result = RobustWatermark.embed(source, payload: qq)
                    } else {
                        result = DCTWatermark.embed(source, qq: qq)
                    }
                    if let result {
                        var name = MediaStore.generateFileName(qq: qq, index: flat)
                        if let ext = item.name.split(separator: ".").last, !ext.isEmpty {
                            name = name.replacingOccurrences(of: ".png", with: "." + ext.lowercased())
                        }
                        if let url = MediaStore.save(result, directory: outputDir, fileName: name) {
                            produced.append(url)
                        }
                    }
                    index += 1
                    let completed = index
                    DispatchQueue.main.async {
                        self.embedProgress = Double(completed) / Double(total)
                        self.embedStatus = "正在打标: \(completed)/\(total)"
                    }
                }
            }
            let success = produced.count
            DispatchQueue.main.async {
                self.watermarkedFiles = produced
                self.embedRunning = false
                self.embedProgress = 1
                self.embedStatus = ""
                self.embedResultText = "打标完成！成功 \(success)/\(total) 张"
                self.toast = "打标完成: \(success)/\(total)"
            }
        }
    }

    func exportZips() {
        guard !watermarkedFiles.isEmpty else {
            toast = "没有已打标的图片"
            return
        }
        let files = watermarkedFiles
        let zipsDir = MediaStore.zipDirectory()
        embedResultText = "正在生成压缩包..."
        queue.async {
            var grouped: [String: [URL]] = [:]
            for file in files {
                guard let qq = MediaStore.extractQQFromFileName(file.lastPathComponent) else { continue }
                grouped[qq, default: []].append(file)
            }
            var zips: [URL] = []
            for (qq, urls) in grouped.sorted(by: { $0.key < $1.key }) {
                let target = zipsDir.appendingPathComponent(MediaStore.zipName(forQQ: qq))
                if let result = try? ZipUtil.zip(files: urls, to: target) {
                    zips.append(result)
                }
            }
            DispatchQueue.main.async {
                self.generatedZips = zips
                if zips.isEmpty {
                    self.embedResultText = "压缩包生成失败"
                    self.toast = "压缩包生成失败"
                } else {
                    self.embedResultText = "已生成压缩包:\n" + zips.map(\.lastPathComponent).joined(separator: "\n")
                    self.toast = "已生成 \(zips.count) 个压缩包"
                }
            }
        }
    }

    func sendEmails() {
        guard emailConfig.isValid else {
            toast = "请先在设置中配置邮箱"
            showEmailConfig = true
            return
        }
        guard !generatedZips.isEmpty else {
            toast = "请先生成压缩包再发送"
            exportZips()
            return
        }
        let zips = generatedZips
        let config = emailConfig
        let groupedCounts: [String: Int] = Dictionary(
            grouping: watermarkedFiles.compactMap { MediaStore.extractQQFromFileName($0.lastPathComponent) },
            by: { $0 }
        ).mapValues(\.count)

        embedResultText = "正在发送邮件..."
        queue.async {
            var sent = 0
            var lines: [String] = []
            for zip in zips {
                guard let qq = MediaStore.extractQQFromZipName(zip.lastPathComponent) else { continue }
                let recipient = EmailUtil.qqToEmail(qq)
                let subject = "您的隐形水印图片 - QQ:\(qq)"
                let total = groupedCounts[qq] ?? 0
                let html = """
                <html><body><h3>隐形水印图片</h3><p>QQ号 <b>\(qq)</b> 对应的水印图片已打包在附件中。</p>\
                <p>共 \(total) 张图片。</p><p>水印采用DCT频域嵌入，抗剪裁、抗压缩。</p></body></html>
                """
                do {
                    try EmailUtil.send(config: config,
                                       to: recipient,
                                       subject: subject,
                                       htmlBody: html,
                                       attachment: zip)
                    sent += 1
                    lines.append("✓ \(recipient)")
                } catch {
                    lines.append("✗ \(recipient) \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                self.embedResultText = "发送结果 (\(sent)/\(zips.count)):\n" + lines.joined(separator: "\n")
                self.toast = "发送完成: \(sent)/\(zips.count)"
            }
        }
    }

    func saveToPhotos() {
        guard !watermarkedFiles.isEmpty else {
            toast = "没有已打标的图片"
            return
        }
        #if canImport(UIKit)
        let files = watermarkedFiles
        Task {
            let status = await PhotoSaver.requestAuthorization()
            guard status else {
                toast = "需要相册权限"
                return
            }
            var saved = 0
            for (offset, file) in files.enumerated() {
                guard let image = Encoder.decode(url: file) else { continue }
                let qq = MediaStore.extractQQFromFileName(file.lastPathComponent)
                let name = (qq.map { "水印_\($0)_" } ?? "水印_") + String(format: "%04d.png", offset + 1)
                if await PhotoSaver.save(image, named: name) { saved += 1 }
            }
            await MainActor.run {
                embedResultText = "已保存 \(saved)/\(files.count) 张图片到相册（DCIM/隐形水印/）"
                toast = "已保存 \(saved)/\(files.count) 张到相册"
            }
        }
        #else
        toast = "相册保存仅在 iOS 可用"
        #endif
    }

    // MARK: - Detection

    func detectImages(_ urls: [URL], names: [String]) {
        guard !urls.isEmpty else { return }
        detectRunning = true
        detectProgress = 0
        detectResults = urls.enumerated().map { DetectItem(name: names[$0.offset], qq: nil, detected: false) }
        detectStatus = "正在检测: 0/\(urls.count)"

        queue.async {
            var results: [DetectItem] = []
            for (index, url) in urls.enumerated() {
                var found: String?
                if let image = Encoder.loadAndDownsample(url: url) {
                    found = RobustWatermark.detect(image) ?? DCTWatermark.detect(image)
                }
                results.append(DetectItem(name: names[index], qq: found, detected: found != nil))
                let done = index + 1
                DispatchQueue.main.async {
                    self.detectProgress = Double(done) / Double(urls.count)
                    self.detectStatus = "正在检测: \(done)/\(urls.count)"
                }
            }
            let hits = results.filter(\.detected).count
            DispatchQueue.main.async {
                self.detectResults = results
                self.detectRunning = false
                self.detectStatus = ""
                self.toast = "检测完成: \(hits)/\(results.count) 张图片含水印"
            }
        }
    }

    func detectZip(_ url: URL) {
        detectRunning = true
        detectStatus = "正在解压压缩包..."
        let destination = MediaStore.tempDirectory().appendingPathComponent(UUID().uuidString, isDirectory: true)
        queue.async {
            do {
                let images = try ZipUtil.unzipImages(url, to: destination)
                DispatchQueue.main.async {
                    self.detectStatus = ""
                    self.detectImages(images, names: images.map(\.lastPathComponent))
                }
            } catch {
                DispatchQueue.main.async {
                    self.detectRunning = false
                    self.detectStatus = ""
                    self.toast = "解压失败：\(error.localizedDescription)"
                }
            }
        }
    }

    func clearDetection() {
        detectResults = []
        detectProgress = 0
        detectStatus = ""
    }
}

public struct PickedImage: Identifiable, Equatable {
    public let id = UUID()
    public let url: URL
    public let name: String
    public let thumbnail: Data?
}

public struct DetectItem: Identifiable, Equatable {
    public let id = UUID()
    public let name: String
    public let qq: String?
    public let detected: Bool
}
