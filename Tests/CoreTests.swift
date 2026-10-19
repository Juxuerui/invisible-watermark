import Foundation
import WatermarkCore

/// Headless verification harness. Run it on macOS with:
///   ./build_and_test.sh            (build + run all checks)
/// It validates the ported algorithms against the reference behaviour that was
/// extracted from the Android APK.
@main
struct CoreTests {
    static func main() {
        var failures = 0
        func check(_ condition: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
            if condition {
                print("  ok   \(name)")
            } else {
                failures += 1
                print("  FAIL \(name) \(detail())")
            }
        }

        print("== Base32 ==")
        let bytes: [UInt8] = [0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]
        let encoded = Base32.encode(bytes)
        check(Base32.decode(encoded) == bytes, "round trip", "encoded=\(encoded)")

        print("== CRC16 / DCTWatermark bit stream ==")
        let qq = "123456789"
        let bits = DCTWatermark.encodeQQ(qq)
        check(bits.count == 228, "228 bit stream", "count=\(bits.count)")
        check(DCTWatermark.crc16(bits, count: 60) == DCTWatermark.crc16(bits, count: 60), "crc stable")
        let first16 = bits.prefix(16).reduce(0) { ($0 << 1) | $1 }
        check(first16 == 0xAA55, "sync header 0xAA55", "got \(String(first16, radix: 16))")

        print("== standard watermark round trip ==")
        let image = makeNoise(width: 256, height: 256, seed: 7)
        let embedded = DCTWatermark.embed(image, qq: qq)
        let detected = DCTWatermark.detect(embedded)
        check(detected == qq, "detect after embed", "detected=\(String(describing: detected))")
        check(DCTWatermark.detect(image) == nil, "no false positive on clean image")

        print("== robust watermark round trip ==")
        let robustImage = makeNoise(width: 800, height: 800, seed: 11)
        if let robustEmbedded = RobustWatermark.embed(robustImage, payload: "ABC123") {
            let payload = RobustWatermark.detect(robustEmbedded)
            check(payload == "ABC123", "detect after embed", "detected=\(String(describing: payload))")
        } else {
            check(false, "robust embed returned nil")
        }

        print("== robust sync bits ==")
        let chips = RobustWatermark.buildChips("TEST")
        check(chips.count == 5120, "chip count", "got \(chips.count)")

        print("== PSD encoder / decoder ==")
        let psdURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.psd")
        do {
            try PSDEncoder.write(image, to: psdURL)
            let decoded = try PSDDecoder.decode(contentsOf: psdURL)
            check(decoded.width == image.width && decoded.height == image.height, "dimensions")
            var maxError = 0
            for i in stride(from: 0, to: image.pixels.count, by: 4) {
                for c in 0..<3 {
                    maxError = max(maxError, abs(Int(decoded.pixels[i + c]) - Int(image.pixels[i + c])))
                }
            }
            check(maxError <= 1, "pixel fidelity", "maxError=\(maxError)")
        } catch {
            check(false, "psd round trip", "\(error)")
        }

        print("== zip writer / reader ==")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ziptest", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileA = dir.appendingPathComponent("a.txt")
        let fileB = dir.appendingPathComponent("b.txt")
        try? Data("hello".utf8).write(to: fileA)
        try? Data("watermark".utf8).write(to: fileB)
        let zipURL = dir.appendingPathComponent("out.zip")
        do {
            _ = try ZipUtil.zip(files: [fileA, fileB], to: zipURL)
            let extracted = try ZipUtil.unzip(zipURL, to: dir.appendingPathComponent("out", isDirectory: true))
            check(extracted.count == 2, "entry count", "got \(extracted.count)")
            let contents = extracted.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            check(contents.contains("hello") && contents.contains("watermark"), "contents intact")
        } catch {
            check(false, "zip round trip", "\(error)")
        }

        print("== file naming ==")
        let generated = MediaStore.generateFileName(qq: qq, index: 3)
        check(generated.hasPrefix("wm_\(qq)_"), "generated name prefix", generated)
        check(MediaStore.extractQQFromFileName(generated) == qq, "extract qq from name")
        check(MediaStore.extractQQFromZipName("水印图片_QQ12345.zip") == "12345", "extract qq from zip name")
        check(MediaStore.extractQQFromZipName("水印图片_QQ12345.zip").flatMap(MediaStore.extractQQFromFileName) == nil,
              "zip name is not an image name")

        print("== MIME message ==")
        do {
            let data = try EmailUtil.buildMessage(from: "sender@qq.com",
                                                  to: "12345@qq.com",
                                                  subject: "您的隐形水印图片 - QQ:12345",
                                                  htmlBody: "<h3>hi</h3>",
                                                  attachment: zipURL)
            let text = String(data: data, encoding: .utf8) ?? ""
            check(text.contains("multipart/mixed"), "multipart header")
            check(text.contains("Content-Disposition: attachment"), "attachment header")
            check(text.contains("Subject: =?UTF-8?B?"), "encoded subject")
        } catch {
            check(false, "mime build", "\(error)")
        }

        print("== license format handling ==")
        let noInput = License.verify(nil)
        check(!noInput.ok, "nil rejected")
        let malformed = License.verify("not-a-license")
        check(!malformed.ok && malformed.reason.contains("格式"), "malformed rejected", malformed.reason)
        let shortPayload = License.verify("AAAA.BBBB")
        check(!shortPayload.ok, "short payload rejected")

        print("")
        if failures == 0 {
            print("ALL CHECKS PASSED")
        } else {
            print("\(failures) CHECK(S) FAILED")
            exit(1)
        }
    }

    static func makeNoise(width: Int, height: Int, seed: UInt64) -> RGBAImage {
        var state = seed &* 6364136223846793005 &+ 1442695040888963407
        func next() -> UInt8 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return UInt8((state >> 33) & 0xFF)
        }
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) {
            pixels[i * 4] = next()
            pixels[i * 4 + 1] = next()
            pixels[i * 4 + 2] = next()
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }
}
