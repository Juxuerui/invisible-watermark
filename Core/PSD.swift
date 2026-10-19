import Foundation

/// Minimal flattened PSD writer, ported from PSDEncoder.
/// Layout: signature, version 1, 6 reserved bytes, 4 channels, height, width,
/// depth 8, colour mode 3 (RGB), empty colour mode data, empty resources,
/// empty layer info, then planar R, G, B, A channel data.
public enum PSDEncoder {

    public enum Error: Swift.Error { case writeFailed }

    public static func write(_ image: RGBAImage, to url: URL) throws {
        var data = Data()
        data.append(contentsOf: [0x38, 0x42, 0x50, 0x53])   // 8BPS
        appendUInt16(&data, 1)
        data.append(contentsOf: [0, 0, 0, 0, 0, 0])
        appendUInt16(&data, 4)
        appendUInt32(&data, UInt32(image.height))
        appendUInt32(&data, UInt32(image.width))
        appendUInt16(&data, 8)
        appendUInt16(&data, 3)
        appendUInt32(&data, 0)   // colour mode data length
        appendUInt32(&data, 0)   // image resources length
        appendUInt32(&data, 0)   // layer and mask info length
        appendUInt16(&data, 0)   // compression: raw

        let count = image.width * image.height
        var channel = [UInt8](repeating: 0, count: count)
        for pass in 0..<4 {
            for i in 0..<count {
                channel[i] = image.pixels[i * 4 + pass]
            }
            data.append(contentsOf: channel)
        }
        do {
            try data.write(to: url)
        } catch {
            throw Error.writeFailed
        }
    }

    static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }
}

/// PSD reader supporting raw and RLE compressed RGB(A), ported from PSDDecoder.
public enum PSDDecoder {

    public enum Error: Swift.Error { case invalidHeader, unsupported, truncated }

    public static func decode(contentsOf url: URL) throws -> RGBAImage {
        let data = try Data(contentsOf: url)
        return try decode(data: data)
    }

    public static func decode(data: Data) throws -> RGBAImage {
        var reader = Reader(data: data)
        let signature = try reader.readBytes(4)
        guard signature == [0x38, 0x42, 0x50, 0x53] else { throw Error.invalidHeader }
        guard try reader.readUInt16() == 1 else { throw Error.invalidHeader }
        try reader.skip(6)
        let channels = Int(try reader.readUInt16())
        let height = Int(try reader.readUInt32())
        let width = Int(try reader.readUInt32())
        let depth = Int(try reader.readUInt16())
        let colorMode = Int(try reader.readUInt16())
        guard width > 0, height > 0, width <= 8192, height <= 8192 else { throw Error.unsupported }
        guard depth == 8, colorMode == 3, channels == 3 || channels == 4 else { throw Error.unsupported }

        let colorModeLength = Int(try reader.readUInt32())
        try reader.skip(colorModeLength)
        let resourceLength = Int(try reader.readUInt32())
        try reader.skip(resourceLength)
        let layerLength = Int(try reader.readUInt32())
        try reader.skip(layerLength)

        let compression = Int(try reader.readUInt16())
        let pixelCount = width * height
        var planes = [[UInt8]](repeating: [UInt8](repeating: 0, count: pixelCount), count: channels)

        switch compression {
        case 0:
            for c in 0..<channels {
                planes[c] = try reader.readBytes(pixelCount)
            }
        case 1:
            var rowCounts = [Int](repeating: 0, count: channels * height)
            for i in 0..<rowCounts.count {
                rowCounts[i] = Int(try reader.readUInt16())
            }
            for c in 0..<channels {
                for y in 0..<height {
                    let rowLength = rowCounts[c * height + y]
                    let packed = try reader.readBytes(rowLength)
                    planes[c][(y * width)..<((y + 1) * width)] =
                        try decodePackBits(packed, expected: width)[...]
                }
            }
        default:
            throw Error.unsupported
        }

        var pixels = [UInt8](repeating: 255, count: pixelCount * 4)
        for i in 0..<pixelCount {
            pixels[i * 4] = planes[0][i]
            pixels[i * 4 + 1] = planes[1][i]
            pixels[i * 4 + 2] = planes[2][i]
            pixels[i * 4 + 3] = channels >= 4 ? planes[3][i] : 255
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    static func decodePackBits(_ input: [UInt8], expected: Int) throws -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(expected)
        var i = 0
        while i < input.count, out.count < expected {
            let header = Int(Int8(bitPattern: input[i]))
            i += 1
            if header >= 0 {
                let count = header + 1
                guard i + count <= input.count else { throw Error.truncated }
                out.append(contentsOf: input[i..<(i + count)])
                i += count
            } else if header != -128 {
                let count = 1 - header
                guard i < input.count else { throw Error.truncated }
                let value = input[i]
                i += 1
                out.append(contentsOf: repeatElement(value, count: count))
            }
        }
        if out.count < expected {
            out.append(contentsOf: repeatElement(0, count: expected - out.count))
        }
        return Array(out.prefix(expected))
    }

    struct Reader {
        let data: Data
        var offset = 0

        init(data: Data) { self.data = data }

        mutating func readBytes(_ count: Int) throws -> [UInt8] {
            guard count >= 0, offset + count <= data.count else { throw Error.truncated }
            let slice = [UInt8](data[offset..<(offset + count)])
            offset += count
            return slice
        }

        mutating func readUInt16() throws -> UInt16 {
            let bytes = try readBytes(2)
            return (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
        }

        mutating func readUInt32() throws -> UInt32 {
            let bytes = try readBytes(4)
            return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) |
                   (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
        }

        mutating func skip(_ count: Int) throws {
            guard count >= 0, offset + count <= data.count else { throw Error.truncated }
            offset += count
        }
    }
}
