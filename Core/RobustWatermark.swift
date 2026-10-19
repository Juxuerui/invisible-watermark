import Foundation

/// Spread spectrum watermark used by the "robust" mode.
///
/// Every 8x8 block carries one chip. A chip is a QIM adjustment of three
/// mid-frequency coefficient pairs. The 160 payload chips (32 bits sync +
/// 128 bits ASCII payload) are repeated across a pseudo randomly shuffled
/// block order and de-spread with a seeded PN sequence.
public enum RobustWatermark {

    static let blockSize = 8
    static let dataBits = 128
    static let syncBits = 32
    static let totalBits = 160
    static let chipCopies = 32
    static let totalChipBits = totalBits * chipCopies // 5120
    static let tiles = 40960
    static let syncValue: UInt64 = 3_039_507_671 // 0xB52B34D7
    static let seed: UInt64 = 9_172_315_309_759_666_981
    static let shuffleSeed: UInt64 = 9_172_315_309_759_740_000
    static let step = 16.0
    static let guardBand = 8.0
    /// Implementation specific clamp: negative targets never go below -0.5.
    static let negativeFloor = -0.5

    /// (rowA, colA, rowB, colB)
    static let pairs: [(Int, Int, Int, Int)] = [
        (1, 2, 2, 1),
        (1, 3, 3, 1),
        (2, 3, 3, 2)
    ]

    struct LCG {
        var state: UInt64
        mutating func nextBit() -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) & 1)
        }
    }

    // MARK: - Chips

    public static func buildChips(_ payload: String) -> [Int] {
        var base = [Int](repeating: 0, count: totalBits)
        for i in 0..<syncBits {
            base[i] = Int((syncValue >> UInt64(31 - i)) & 1)
        }
        let bytes = Array(payload.utf8)
        for i in 0..<dataBits {
            let byteIndex = i / 8
            if byteIndex < bytes.count {
                base[syncBits + i] = Int((bytes[byteIndex] >> UInt8(7 - (i % 8))) & 1)
            }
        }
        var rng = LCG(state: seed)
        var out = [Int](repeating: 0, count: totalChipBits)
        for chip in 0..<totalBits {
            for k in 0..<chipCopies {
                out[chip * chipCopies + k] = rng.nextBit() ^ base[chip]
            }
        }
        return out
    }

    /// The original seeds the LCG but never advances it while shuffling, so the
    /// shuffle is fully deterministic and identical for embed and detect.
    static func shuffledOrder(_ total: Int) -> [Int] {
        var order = Array(0..<total)
        guard total > 1 else { return order }
        let value = shuffleSeed >> 33
        for i in stride(from: total - 1, to: 0, by: -1) {
            let index = Int(value % UInt64(i + 1))
            order.swapAt(i, index)
        }
        return order
    }

    // MARK: - Embedding

    public static func embed(_ image: RGBAImage, payload: String) -> RGBAImage? {
        guard image.width >= blockSize, image.height >= blockSize else { return nil }
        var working = image
        let columns = (image.width - blockSize) / blockSize + 1
        let rows = (image.height - blockSize) / blockSize + 1
        let total = columns * rows
        let chips = buildChips(payload)
        let order = shuffledOrder(total)
        // The original embeds min(blockCount, chips.length * 8) chips.
        let count = min(total, chips.count * 8)

        for i in 0..<count {
            let index = order[i]
            let bx = (index % columns) * blockSize
            let by = (index / columns) * blockSize
            embedChip(&working, x: bx, y: by, bit: chips[i % chips.count])
        }
        return working
    }

    static func embedChip(_ image: inout RGBAImage, x: Int, y: Int, bit: Int) {
        let block = image.block(x: x, y: y)
        var coef = DCT.forward(block)
        for (r1, c1, r2, c2) in pairs {
            let difference = coef[r1][c1] - coef[r2][c2]
            var target: Double
            if bit == 1 {
                target = floor((difference + guardBand) / step) * step + guardBand
                if target < guardBand { target = guardBand }
            } else {
                target = ceil((difference - guardBand) / step) * step - guardBand
                if target > negativeFloor { target = negativeFloor }
            }
            let adjustment = (target - difference) / 2.0
            coef[r1][c1] += adjustment
            coef[r2][c2] -= adjustment
        }
        let restored = DCT.inverse(coef)
        image.writeBlock(x: x, y: y, values: restored)
    }

    static func readChip(_ image: RGBAImage, x: Int, y: Int) -> Double {
        let block = image.block(x: x, y: y)
        let coef = DCT.forward(block)
        var sum = 0.0
        for (r1, c1, r2, c2) in pairs {
            sum += coef[r1][c1] - coef[r2][c2]
        }
        return sum
    }

    // MARK: - Detection

    public static func detect(_ image: RGBAImage) -> String? {
        guard image.width >= blockSize, image.height >= blockSize else { return nil }
        let columns = (image.width - blockSize) / blockSize + 1
        let rows = (image.height - blockSize) / blockSize + 1
        let total = columns * rows
        let order = shuffledOrder(total)
        let sampleCount = min(total, tiles)
        guard sampleCount > 0 else { return nil }

        var values = [Double](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            let index = order[i]
            values[i] = readChip(image, x: (index % columns) * blockSize, y: (index / columns) * blockSize)
        }

        var rng = LCG(state: seed)
        var pn = [Int](repeating: 0, count: totalChipBits)
        for i in 0..<totalChipBits {
            pn[i] = rng.nextBit()
        }

        var chips = [Int](repeating: 0, count: totalBits)
        for chip in 0..<totalBits {
            var accumulator = 0.0
            for copy in 0..<8 {
                for k in 0..<chipCopies {
                    let index = copy * totalChipBits + chip * chipCopies + k
                    if index < sampleCount {
                        let value = values[index]
                        accumulator += (pn[chip * chipCopies + k] == 1) ? -value : value
                    }
                }
            }
            chips[chip] = accumulator < 0 ? 0 : 1
        }

        guard let syncStart = findSync(chips), syncStart >= 0 else { return nil }

        var result = ""
        let dataStart = syncStart + syncBits
        for charIndex in 0..<16 {
            var value = 0
            for bit in 0..<8 {
                let index = dataStart + charIndex * 8 + bit
                if index < chips.count {
                    value |= (chips[index] & 1) << (7 - bit)
                }
            }
            if value == 0 { break }
            if let scalar = UnicodeScalar(value), value >= 32 || value == 10 || value == 13 {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    static func findSync(_ chips: [Int]) -> Int? {
        var bestScore = -1
        var bestPosition = -1
        for position in 0...128 {
            guard position + syncBits <= chips.count else { break }
            var score = 0
            for i in 0..<syncBits {
                if chips[position + i] == Int((syncValue >> UInt64(31 - i)) & 1) {
                    score += 1
                }
            }
            if score > bestScore {
                bestScore = score
                bestPosition = position
            }
        }
        return bestScore >= 24 ? bestPosition : nil
    }
}
