import Foundation

/// Standard "QQ number" watermark.
///
/// Bit stream (76 bits, repeated three times = 228 bits):
///   16 bit sync 0xAA55
///   11 digits x 4 bit (each digit BCD, left padded to 11 characters)
///   16 bit CRC16-CCITT over the first 60 bits
///
/// Embedding quantizes the difference of three mid frequency coefficient pairs
/// inside every 8x8 luma block.
public enum DCTWatermark {

    static let sync: UInt16 = 0xAA55
    static let payloadBits = 76
    static let repeatCount = 3

    /// (rowA, colA, rowB, colB)
    static let pairs: [(Int, Int, Int, Int)] = [
        (4, 2, 2, 4),
        (5, 1, 1, 5),
        (5, 3, 3, 5)
    ]
    /// The original pushes the pair apart by +/- 6.0 around the mean.
    static let offset = 6.0

    // MARK: - Bit stream

    public static func encodeQQ(_ qq: String) -> [Int] {
        let digits = pad(qq)
        var bits: [Int] = []
        bits.reserveCapacity(payloadBits)
        for i in stride(from: 15, through: 0, by: -1) {
            bits.append(Int((sync >> UInt16(i)) & 1))
        }
        for ch in digits {
            let value = Int(String(ch)) ?? 0
            for i in stride(from: 3, through: 0, by: -1) {
                bits.append((value >> i) & 1)
            }
        }
        let crc = crc16(bits, count: 60)
        for i in stride(from: 15, through: 0, by: -1) {
            bits.append(Int((crc >> UInt16(i)) & 1))
        }
        var repeated: [Int] = []
        repeated.reserveCapacity(payloadBits * repeatCount)
        for _ in 0..<repeatCount {
            repeated.append(contentsOf: bits)
        }
        return repeated
    }

    static func pad(_ qq: String) -> String {
        let trimmed = String(qq.prefix(11))
        if trimmed.count >= 11 { return trimmed }
        return String(repeating: "0", count: 11 - trimmed.count) + trimmed
    }

    static func crc16(_ bits: [Int], count: Int) -> UInt16 {
        var crc: UInt32 = 0xFFFF
        for i in 0..<count {
            crc ^= UInt32(bits[i]) << 15
            if (crc & 0x8000) != 0 {
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            } else {
                crc = (crc << 1) & 0xFFFF
            }
        }
        return UInt16(crc & 0xFFFF)
    }

    /// Decode a 76 bit payload block. Returns nil when sync / digit / CRC fail,
    /// matching the original which returns null in those cases.
    static func decodeQQ(_ bits: [Int]) -> String? {
        guard bits.count >= payloadBits else { return nil }
        var syncValue = 0
        for i in 0..<16 {
            syncValue = (syncValue << 1) | bits[i]
        }
        guard syncValue == Int(sync) else { return nil }

        var digits = ""
        for k in 0..<11 {
            var value = 0
            for j in 0..<4 {
                value = (value << 1) | bits[16 + k * 4 + j]
            }
            guard value <= 9 else { return nil }
            digits.append(String(value))
        }

        var crcValue = 0
        for i in 0..<16 {
            crcValue = (crcValue << 1) | bits[60 + i]
        }
        guard crcValue == Int(crc16(bits, count: 60)) else { return nil }

        let trimmed = digits.drop(while: { $0 == "0" })
        return trimmed.isEmpty ? nil : String(trimmed)
    }

    // MARK: - Embedding

    public static func embed(_ image: RGBAImage, qq: String) -> RGBAImage {
        guard image.width >= 8, image.height >= 8 else { return image }
        let columns = image.width / 8
        let rows = image.height / 8
        guard columns >= 1, rows >= 1 else { return image }

        let bits = encodeQQ(qq)
        var working = image
        var bitIndex = 0
        for blockRow in 0..<rows {
            for blockCol in 0..<columns {
                let block = working.block(x: blockCol * 8, y: blockRow * 8)
                var coef = DCT.forward(block)
                embedBit(&coef, bit: bits[bitIndex % bits.count])
                let restored = DCT.inverse(coef)
                working.writeBlock(x: blockCol * 8, y: blockRow * 8, values: restored)
                bitIndex += 1
            }
        }
        return working
    }

    static func embedBit(_ coef: inout [[Double]], bit: Int) {
        for (r1, c1, r2, c2) in pairs {
            let average = (coef[r1][c1] + coef[r2][c2]) / 2.0
            if bit == 1 {
                coef[r1][c1] = average + offset
                coef[r2][c2] = average - offset
            } else {
                coef[r1][c1] = average - offset
                coef[r2][c2] = average + offset
            }
        }
    }

    static func extractBit(_ coef: [[Double]]) -> Int {
        var votes = 0
        for (r1, c1, r2, c2) in pairs {
            if coef[r1][c1] > coef[r2][c2] { votes += 1 }
        }
        return votes >= 2 ? 1 : 0
    }

    // MARK: - Detection

    public static func detect(_ image: RGBAImage) -> String? {
        let columns = image.width / 8
        let rows = image.height / 8
        guard columns >= 1, rows >= 1 else { return nil }

        var bits: [Int] = []
        bits.reserveCapacity(columns * rows)
        for blockRow in 0..<rows {
            for blockCol in 0..<columns {
                let block = image.block(x: blockCol * 8, y: blockRow * 8)
                bits.append(extractBit(DCT.forward(block)))
            }
        }
        return detectFromBits(bits)
    }

    static func detectFromBits(_ bits: [Int]) -> String? {
        let count = bits.count
        guard count >= payloadBits else { return nil }

        var best: String?
        var bestScore = 0
        var bestOffset = -1

        if count >= 228 {
            // Original iterates offset 0..<min(228, count) and only accepts
            // offsets that still leave a full 228 bit window.
            let maxOffset = min(count - 228, 227)
            if maxOffset >= 0 {
                for offset in 0...maxOffset {
                    guard count - offset >= 228 else { break }
                    let slice = Array(bits[offset..<(offset + 228)])
                    guard let candidate = decodeQQ(majorityVote(slice)) else { continue }
                    let pattern = encodeQQ(candidate)
                    var matches = 0
                    var index = 0
                    while offset + index < count {
                        if bits[offset + index] == pattern[index % pattern.count] {
                            matches += 1
                        }
                        index += 1
                    }
                    if matches > bestScore {
                        best = candidate
                        bestOffset = offset
                        bestScore = matches
                    }
                }
            }
            if bestOffset >= 0 {
                if let refined = decodeQQ(enhancedMajorityVote(bits, start: bestOffset)) {
                    best = refined
                }
            }
        }

        if best == nil, count >= payloadBits, count < 228 {
            best = detectWithCorrelation(bits)
        }

        if best == nil, count >= 228 {
            let slice = Array(bits[0..<228])
            best = decodeQQ(majorityVote(slice))
        }
        return best
    }

    static func majorityVote(_ slice: [Int]) -> [Int] {
        var out = [Int](repeating: 0, count: payloadBits)
        for i in 0..<payloadBits {
            var ones = 0
            for k in 0..<3 {
                let index = k * payloadBits + i
                if index < slice.count, slice[index] == 1 { ones += 1 }
            }
            out[i] = ones > 1 ? 1 : 0
        }
        return out
    }

    static func enhancedMajorityVote(_ bits: [Int], start: Int) -> [Int] {
        var out = [Int](repeating: 0, count: payloadBits)
        for i in 0..<payloadBits {
            var ones = 0
            var zeros = 0
            var k = 0
            while true {
                let index = k * payloadBits + start + i
                if index >= bits.count { break }
                if bits[index] == 1 { ones += 1 } else { zeros += 1 }
                k += 1
            }
            out[i] = ones > zeros ? 1 : 0
        }
        return out
    }

    static func detectWithCorrelation(_ bits: [Int]) -> String? {
        let count = bits.count
        var bestOffset = -1
        var bestMatches = 0
        var bestSlice: [Int] = []

        var offset = 0
        while offset <= count - payloadBits {
            let slice = Array(bits[offset..<(offset + payloadBits)])
            if decodeQQ(slice) != nil {
                var matches = 0
                var compared = 0
                var i = 0
                while i < payloadBits, offset + payloadBits + i < count {
                    if bits[offset + i] == bits[offset + payloadBits + i] { matches += 1 }
                    compared += 1
                    i += 1
                }
                if compared > 0, matches > bestMatches {
                    bestMatches = matches
                    bestOffset = offset
                    bestSlice = slice
                }
            }
            offset += 1
        }

        guard bestOffset >= 0 else { return nil }

        var voted = [Int](repeating: 0, count: payloadBits)
        for i in 0..<payloadBits {
            var ones = 0
            var zeros = 0
            var k = 0
            while true {
                let index = k * payloadBits + bestOffset + i
                if index >= count { break }
                if bits[index] == 1 { ones += 1 } else { zeros += 1 }
                k += 1
            }
            voted[i] = ones < zeros ? 0 : 1
        }
        return decodeQQ(voted) ?? decodeQQ(bestSlice)
    }
}
