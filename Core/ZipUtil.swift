import Foundation
#if canImport(FoundationArchive)
import FoundationArchive
#endif

/// Zip creation / extraction. iOS has no built in zip API, so this is a small
/// store-only (method 0) implementation. Store-only archives are valid zip files
/// readable by any unzip tool, and they keep the port self contained.
public enum ZipUtil {

    public enum Error: Swift.Error { case invalidArchive, unsupportedCompression, writeFailed }

    // MARK: - Writing

    public static func zip(files: [URL], to destination: URL) throws -> URL {
        var archive = Data()
        var central = Data()
        var entries = 0

        for file in files {
            guard let contents = try? Data(contentsOf: file) else { continue }
            let name = file.lastPathComponent
            guard let nameData = name.data(using: .utf8) else { continue }
            let crc = crc32(contents)
            let localOffset = UInt32(archive.count)

            appendUInt32(&archive, 0x04034b50)
            appendUInt16(&archive, 10)              // version needed
            appendUInt16(&archive, 0x0800)          // UTF-8 flag
            appendUInt16(&archive, 0)               // store
            appendUInt16(&archive, 0)               // time
            appendUInt16(&archive, 0)               // date
            appendUInt32(&archive, crc)
            appendUInt32(&archive, UInt32(contents.count))
            appendUInt32(&archive, UInt32(contents.count))
            appendUInt16(&archive, UInt16(nameData.count))
            appendUInt16(&archive, 0)
            archive.append(nameData)
            archive.append(contents)

            appendUInt32(&central, 0x02014b50)
            appendUInt16(&central, 20)              // version made by
            appendUInt16(&central, 10)              // version needed
            appendUInt16(&central, 0x0800)
            appendUInt16(&central, 0)
            appendUInt16(&central, 0)
            appendUInt16(&central, 0)
            appendUInt32(&central, crc)
            appendUInt32(&central, UInt32(contents.count))
            appendUInt32(&central, UInt32(contents.count))
            appendUInt16(&central, UInt16(nameData.count))
            appendUInt16(&central, 0)               // extra
            appendUInt16(&central, 0)               // comment
            appendUInt16(&central, 0)               // disk
            appendUInt16(&central, 0)               // internal attrs
            appendUInt32(&central, 0)               // external attrs
            appendUInt32(&central, localOffset)
            central.append(nameData)
            entries += 1
        }

        guard entries > 0 else { throw Error.writeFailed }
        let centralOffset = UInt32(archive.count)
        archive.append(central)
        appendUInt32(&archive, 0x06054b50)
        appendUInt16(&archive, 0)
        appendUInt16(&archive, 0)
        appendUInt16(&archive, UInt16(entries))
        appendUInt16(&archive, UInt16(entries))
        appendUInt32(&archive, UInt32(central.count))
        appendUInt32(&archive, centralOffset)
        appendUInt16(&archive, 0)

        do {
            try archive.write(to: destination)
        } catch {
            throw Error.writeFailed
        }
        return destination
    }

    // MARK: - Reading

    /// Extract all files, guarding against path traversal like the original
    /// (`entry.contains("..")` aborts extraction).
    @discardableResult
    public static func unzip(_ archive: URL, to directory: URL) throws -> [URL] {
        let data = try Data(contentsOf: archive)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var extracted: [URL] = []
        var offset = 0
        while offset + 30 <= data.count {
            let signature = readUInt32(data, offset)
            guard signature == 0x04034b50 else { break }
            let flags = readUInt16(data, offset + 6)
            let method = readUInt16(data, offset + 8)
            let compressedSize = Int(readUInt32(data, offset + 18))
            let nameLength = Int(readUInt16(data, offset + 26))
            let extraLength = Int(readUInt16(data, offset + 28))
            let nameStart = offset + 30
            guard nameStart + nameLength <= data.count else { throw Error.invalidArchive }
            let nameData = data[nameStart..<(nameStart + nameLength)]
            let name = String(data: nameData, encoding: .utf8) ?? ""
            let dataStart = nameStart + nameLength + extraLength

            if (flags & 0x0008) != 0 {
                throw Error.unsupportedCompression
            }
            guard dataStart + compressedSize <= data.count else { throw Error.invalidArchive }
            let payload = data[dataStart..<(dataStart + compressedSize)]
            offset = dataStart + compressedSize

            guard !name.contains("..") else { throw Error.invalidArchive }
            if name.hasSuffix("/") { continue }
            guard method == 0 else { throw Error.unsupportedCompression }

            let target = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try payload.write(to: target)
            extracted.append(target)
        }
        return extracted
    }

    public static func unzipImages(_ archive: URL, to directory: URL) throws -> [URL] {
        try unzip(archive, to: directory).filter { MediaStore.isImageFile($0.lastPathComponent) }
    }

    // MARK: - Primitives

    static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) |
        (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }

    static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    static let crcTable: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) != 0 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
            }
            return value
        }
    }()

    public static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}
