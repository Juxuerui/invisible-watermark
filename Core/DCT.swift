import Foundation

/// Shared 8x8 DCT machinery. The Android original builds an orthonormal
/// 8x8 matrix and applies it separably, so coefficients match exactly.
enum DCT {
    static let matrix: [[Double]] = {
        var m = [[Double]](repeating: [Double](repeating: 0, count: 8), count: 8)
        for u in 0..<8 {
            let cu = u == 0 ? (1.0 / 8.0).squareRoot() : (2.0 / 8.0).squareRoot()
            for x in 0..<8 {
                m[u][x] = cu * cos(((2.0 * Double(x) + 1.0) * Double(u) * Double.pi) / 16.0)
            }
        }
        return m
    }()

    static let transpose: [[Double]] = {
        var t = [[Double]](repeating: [Double](repeating: 0, count: 8), count: 8)
        for i in 0..<8 {
            for j in 0..<8 {
                t[i][j] = matrix[j][i]
            }
        }
        return t
    }()

    static func forward(_ block: [[Double]]) -> [[Double]] {
        var tmp = [[Double]](repeating: [Double](repeating: 0, count: 8), count: 8)
        for y in 0..<8 {
            for u in 0..<8 {
                var sum = 0.0
                for x in 0..<8 {
                    sum += matrix[u][x] * block[y][x]
                }
                tmp[y][u] = sum
            }
        }
        var out = [[Double]](repeating: [Double](repeating: 0, count: 8), count: 8)
        for v in 0..<8 {
            for u in 0..<8 {
                var sum = 0.0
                for y in 0..<8 {
                    sum += tmp[y][u] * transpose[y][v]
                }
                out[v][u] = sum
            }
        }
        return out
    }

    static func inverse(_ coef: [[Double]]) -> [[Double]] {
        var tmp = [[Double]](repeating: [Double](repeating: 0, count: 8), count: 8)
        for y in 0..<8 {
            for u in 0..<8 {
                var sum = 0.0
                for x in 0..<8 {
                    sum += transpose[u][x] * coef[y][x]
                }
                tmp[y][u] = sum
            }
        }
        var out = [[Double]](repeating: [Double](repeating: 0, count: 8), count: 8)
        for v in 0..<8 {
            for u in 0..<8 {
                var sum = 0.0
                for y in 0..<8 {
                    sum += tmp[y][u] * matrix[y][v]
                }
                out[v][u] = sum
            }
        }
        return out
    }

    static func luma(r: Double, g: Double, b: Double) -> Double {
        r * 0.299 + g * 0.587 + b * 0.114
    }

    static func luma(r: Int, g: Int, b: Int) -> Double {
        Double(r) * 0.299 + Double(g) * 0.587 + Double(b) * 0.114
    }

    static func clamp(_ v: Int) -> UInt8 {
        UInt8(max(0, min(255, v)))
    }
}
