import Foundation

// MARK: - Auto Tone / Auto Contrast / Auto Color

public enum AutoAdjust: String, CaseIterable, Sendable {
    case tone, contrast, color

    public var historyName: String {
        switch self {
        case .tone: return "Auto Tone"
        case .contrast: return "Auto Contrast"
        case .color: return "Auto Color"
        }
    }

    /// Fraction of pixels clipped at each end (Photoshop's default is 0.1%).
    static let clip = 0.001

    /// Returns the adjusted bytes for `rect`.
    public func apply(to buffer: PixelBuffer, rect: IRect) -> [UInt8] {
        var bytes = buffer.copyRegion(rect)
        // Histograms of straight (un-premultiplied) color, ignoring fully transparent pixels.
        var hist = [[Int]](repeating: [Int](repeating: 0, count: 256), count: 3)
        var n = 0
        bytes.withUnsafeBufferPointer { b in
            var i = 0
            while i < b.count {
                let a = Int(b[i + 3])
                if a > 0 {
                    for c in 0..<3 {
                        let v = a == 255 ? Int(b[i + c]) : min(255, Int(b[i + c]) * 255 / a)
                        hist[c][v] += 1
                    }
                    n += 1
                }
                i += 4
            }
        }
        guard n > 0 else { return bytes }

        var luts = [[UInt8]](repeating: Array(0...255).map { UInt8($0) }, count: 3)
        switch self {
        case .tone, .color:
            for c in 0..<3 {
                let (lo, hi) = AutoAdjust.ends(hist[c], total: n)
                luts[c] = AutoAdjust.stretch(lo: lo, hi: hi)
            }
        case .contrast:
            var combined = [Int](repeating: 0, count: 256)
            for v in 0..<256 { combined[v] = hist[0][v] + hist[1][v] + hist[2][v] }
            let (lo, hi) = AutoAdjust.ends(combined, total: n * 3)
            let lut = AutoAdjust.stretch(lo: lo, hi: hi)
            luts = [lut, lut, lut]
        }

        if self == .color {
            // Snap neutral midtones: after the stretch, average the near-gray midtone pixels per channel
            // and bend each channel with a gamma curve so those pixels come out neutral.
            var sums = [Double](repeating: 0, count: 3)
            var count = 0
            bytes.withUnsafeBufferPointer { b in
                var i = 0
                while i < b.count {
                    if b[i + 3] == 255 {
                        let r = Int(luts[0][Int(b[i])]), g = Int(luts[1][Int(b[i + 1])]), bl = Int(luts[2][Int(b[i + 2])])
                        let mx = max(r, g, bl), mn = min(r, g, bl)
                        let l = (r + g + bl) / 3
                        if mx - mn < 40 && l > 50 && l < 205 {
                            sums[0] += Double(r)
                            sums[1] += Double(g)
                            sums[2] += Double(bl)
                            count += 1
                        }
                    }
                    i += 4
                }
            }
            if count > max(50, n / 1000) {
                let means = sums.map { $0 / Double(count) }
                let target = (means[0] + means[1] + means[2]) / 3
                for c in 0..<3 {
                    let m = min(max(means[c], 1), 254)
                    let gamma = min(max(log(target / 255) / log(m / 255), 0.6), 1.6)
                    luts[c] = luts[c].map { v in
                        UInt8(min(255, max(0, (255 * pow(Double(v) / 255, gamma)).rounded())))
                    }
                }
            }
        }

        bytes.withUnsafeMutableBufferPointer { b in
            var i = 0
            while i < b.count {
                let a = Int(b[i + 3])
                if a == 255 {
                    b[i] = luts[0][Int(b[i])]
                    b[i + 1] = luts[1][Int(b[i + 1])]
                    b[i + 2] = luts[2][Int(b[i + 2])]
                } else if a > 0 {
                    for c in 0..<3 {
                        let straight = min(255, Int(b[i + c]) * 255 / a)
                        b[i + c] = UInt8(Int(luts[c][straight]) * a / 255)
                    }
                }
                i += 4
            }
        }
        return bytes
    }

    static func ends(_ h: [Int], total: Int) -> (Int, Int) {
        let cut = Int(Double(total) * clip)
        var acc = 0
        var lo = 0
        for v in 0..<256 {
            acc += h[v]
            if acc > cut { lo = v; break }
        }
        acc = 0
        var hi = 255
        for v in stride(from: 255, through: 0, by: -1) {
            acc += h[v]
            if acc > cut { hi = v; break }
        }
        return (lo, hi)
    }

    static func stretch(lo: Int, hi: Int) -> [UInt8] {
        guard hi > lo else { return Array(0...255).map { UInt8($0) } }
        return (0...255).map { v in
            UInt8(min(255, max(0, ((Double(v - lo) * 255) / Double(hi - lo)).rounded())))
        }
    }
}
