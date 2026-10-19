import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#else
import AppKit
public typealias PlatformImage = NSImage
#endif

/// Plain, platform independent RGBA bitmap. All watermarking works on this so
/// the exact same code path runs on iOS and on the macOS test harness.
public struct RGBAImage {
    public let width: Int
    public let height: Int
    /// Row major, 4 bytes per pixel: R, G, B, A (not premultiplied).
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 4, "pixel buffer size mismatch")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, fill: UInt8 = 0) {
        self.width = width
        self.height = height
        self.pixels = [UInt8](repeating: fill, count: width * height * 4)
    }

    @inline(__always)
    public func offset(x: Int, y: Int) -> Int {
        (y * width + x) * 4
    }

    @inline(__always)
    public func rgb(x: Int, y: Int) -> (Int, Int, Int) {
        let o = offset(x: x, y: y)
        return (Int(pixels[o]), Int(pixels[o + 1]), Int(pixels[o + 2]))
    }

    @inline(__always)
    public mutating func setRGB(x: Int, y: Int, r: UInt8, g: UInt8, b: UInt8) {
        let o = offset(x: x, y: y)
        pixels[o] = r
        pixels[o + 1] = g
        pixels[o + 2] = b
    }

    /// Extract the Y (luma) plane at double precision.
    public func lumaPlane() -> [[Double]] {
        var plane = [[Double]](repeating: [Double](repeating: 0, count: width), count: height)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = rgb(x: x, y: y)
                plane[y][x] = DCT.luma(r: r, g: g, b: b)
            }
        }
        return plane
    }

    /// Write a modified luma plane back by applying the same delta to R, G and B,
    /// exactly like the original mergeYChannel implementation.
    public mutating func mergeLuma(_ plane: [[Double]]) {
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = rgb(x: x, y: y)
                let base = DCT.luma(r: r, g: g, b: b)
                let delta = Int(plane[y][x] - base)
                setRGB(x: x, y: y,
                       r: DCT.clamp(r + delta),
                       g: DCT.clamp(g + delta),
                       b: DCT.clamp(b + delta))
            }
        }
    }

    public func block(x: Int, y: Int) -> [[Double]] {
        var b = [[Double]](repeating: [Double](repeating: 0, count: 8), count: 8)
        for dy in 0..<8 {
            for dx in 0..<8 {
                let (r, g, bl) = rgb(x: x + dx, y: y + dy)
                b[dy][dx] = DCT.luma(r: r, g: g, b: bl)
            }
        }
        return b
    }

    public mutating func writeBlock(x: Int, y: Int, values: [[Double]]) {
        for dy in 0..<8 {
            for dx in 0..<8 {
                let (r, g, b) = rgb(x: x + dx, y: y + dy)
                let base = DCT.luma(r: r, g: g, b: b)
                let delta = Int(values[dy][dx] - base)
                setRGB(x: x + dx, y: y + dy,
                       r: DCT.clamp(r + delta),
                       g: DCT.clamp(g + delta),
                       b: DCT.clamp(b + delta))
            }
        }
    }

    // MARK: - Platform bridging

    public init?(platformImage: PlatformImage) {
        #if canImport(UIKit)
        guard let cg = platformImage.cgImage else { return nil }
        #else
        var rect = CGRect(origin: .zero, size: platformImage.size)
        guard let cg = platformImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        #endif
        self.init(cgImage: cg)
    }

    public init?(cgImage: CGImage) {
        let w = cgImage.width
        let h = cgImage.height
        guard w > 0, h > 0 else { return nil }
        let byteCount = w * h * 4
        let raw = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 16)
        defer { raw.deallocate() }
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue |
            CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: raw,
                                  width: w,
                                  height: h,
                                  bitsPerComponent: 8,
                                  bytesPerRow: w * 4,
                                  space: colorSpace,
                                  bitmapInfo: bitmapInfo) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        let buffer = raw.bindMemory(to: UInt8.self, capacity: byteCount)
        var pixels = [UInt8](repeating: 0, count: byteCount)
        for i in 0..<byteCount {
            pixels[i] = buffer[i]
        }
        // Un-premultiply so later edits do not compound rounding error.
        for i in stride(from: 0, to: byteCount, by: 4) {
            let a = Int(pixels[i + 3])
            if a > 0 && a < 255 {
                pixels[i] = UInt8(min(255, Int(pixels[i]) * 255 / a))
                pixels[i + 1] = UInt8(min(255, Int(pixels[i + 1]) * 255 / a))
                pixels[i + 2] = UInt8(min(255, Int(pixels[i + 2]) * 255 / a))
            }
        }
        self.width = w
        self.height = h
        self.pixels = pixels
    }

    public func makeCGImage() -> CGImage? {
        var buffer = pixels
        guard let provider = CGDataProvider(data: Data(buffer) as CFData) else { return nil }
        buffer.removeAll(keepingCapacity: false)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return CGImage(width: width,
                       height: height,
                       bitsPerComponent: 8,
                       bitsPerPixel: 32,
                       bytesPerRow: width * 4,
                       space: colorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: false,
                       intent: .defaultIntent)
    }

    public func platformImage() -> PlatformImage? {
        guard let cg = makeCGImage() else { return nil }
        #if canImport(UIKit)
        return UIImage(cgImage: cg)
        #else
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
        #endif
    }
}
