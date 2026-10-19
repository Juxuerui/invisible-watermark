import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// PNG / JPEG encoding and decoding that works on both iOS and macOS.
public enum Encoder {

    public static func pngData(_ image: RGBAImage) -> Data? {
        guard let cg = image.makeCGImage() else { return nil }
        #if canImport(UIKit)
        return UIImage(cgImage: cg).pngData()
        #else
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
        #endif
    }

    public static func jpegData(_ image: RGBAImage, quality: Double) -> Data? {
        guard let cg = image.makeCGImage() else { return nil }
        #if canImport(UIKit)
        return UIImage(cgImage: cg).jpegData(compressionQuality: quality)
        #else
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        #endif
    }

    /// Decode any supported bitmap. PSD files are routed to the custom decoder.
    public static func decode(url: URL) -> RGBAImage? {
        if url.pathExtension.lowercased() == "psd" {
            return try? PSDDecoder.decode(contentsOf: url)
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data: data)
    }

    public static func decode(data: Data) -> RGBAImage? {
        #if canImport(UIKit)
        guard let ui = UIImage(data: data) else { return nil }
        return RGBAImage(platformImage: ui)
        #else
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        guard let cg = rep.cgImage else { return nil }
        return RGBAImage(cgImage: cg)
        #endif
    }

    /// Downscale so the longest side is at most `maxDimension`, mirroring the
    /// BitmapLoader sampling behaviour (which capped at 4096).
    public static func loadAndDownsample(url: URL, maxDimension: Int = 4096) -> RGBAImage? {
        guard let image = decode(url: url) else { return nil }
        let longest = max(image.width, image.height)
        guard longest > maxDimension else { return image }
        let scale = Double(maxDimension) / Double(longest)
        let width = max(8, Int(Double(image.width) * scale))
        let height = max(8, Int(Double(image.height) * scale))
        return resized(image, width: width, height: height)
    }

    public static func resized(_ image: RGBAImage, width: Int, height: Int) -> RGBAImage? {
        guard let cg = image.makeCGImage() else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = ctx.makeImage() else { return nil }
        return RGBAImage(cgImage: scaled)
    }
}
