import Foundation

/// Photoshop-style Magic Eraser: click a color, and pixels within `tolerance` of it become transparent.
public enum MagicEraser {

    /// - Parameters:
    ///   - tolerance: 0...255, maximum per-channel difference from the clicked color.
    ///   - contiguous: only erase pixels connected to the click; otherwise every matching pixel.
    ///   - antiAlias: soften the 1-pixel edge of the erased area.
    public static func erase(_ buffer: PixelBuffer, x sx: Int, y sy: Int, tolerance: Int,
                             contiguous: Bool, antiAlias: Bool) -> MagicEraseResult? {
        let w = buffer.width, h = buffer.height
        guard sx >= 0, sy >= 0, sx < w, sy < h else { return nil }
        var mask = [UInt8](repeating: 0, count: w * h)
        var minX = w, minY = h, maxX = -1, maxY = -1
        var count = 0

        buffer.pixels.withUnsafeBufferPointer { p in
            let si = (sy * w + sx) * 4
            guard p[si + 3] > 0 else { return }
            let r0 = Int(p[si]), g0 = Int(p[si + 1]), b0 = Int(p[si + 2]), a0 = Int(p[si + 3])
            @inline(__always) func matches(_ i: Int) -> Bool {
                let o = i * 4
                let a = Int(p[o + 3])
                if a == 0 { return false }
                return abs(Int(p[o]) - r0) <= tolerance && abs(Int(p[o + 1]) - g0) <= tolerance
                    && abs(Int(p[o + 2]) - b0) <= tolerance && abs(a - a0) <= tolerance
            }
            @inline(__always) func mark(_ x: Int, _ y: Int) {
                mask[y * w + x] = 255
                count += 1
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
            if contiguous {
                // Scanline flood fill.
                var stack: [(Int, Int)] = [(sx, sy)]
                while let (x0, y) = stack.popLast() {
                    if mask[y * w + x0] != 0 || !matches(y * w + x0) { continue }
                    var l = x0
                    while l > 0 && mask[y * w + l - 1] == 0 && matches(y * w + l - 1) { l -= 1 }
                    var r = x0
                    while r < w - 1 && mask[y * w + r + 1] == 0 && matches(y * w + r + 1) { r += 1 }
                    for x in l...r { mark(x, y) }
                    for ny in [y - 1, y + 1] where ny >= 0 && ny < h {
                        var x = l
                        while x <= r {
                            if mask[ny * w + x] == 0 && matches(ny * w + x) {
                                stack.append((x, ny))
                                // skip the rest of this run; the fill will extend it
                                while x <= r && mask[ny * w + x] == 0 && matches(ny * w + x) { x += 1 }
                            } else {
                                x += 1
                            }
                        }
                    }
                }
            } else {
                for y in 0..<h {
                    for x in 0..<w where matches(y * w + x) { mark(x, y) }
                }
            }
        }
        guard count > 0 else { return nil }

        let rect = IRect(x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1)
            .expanded(by: antiAlias ? 1 : 0).intersection(buffer.bounds)
        var out = buffer.copyRegion(rect)
        for yy in 0..<rect.h {
            for xx in 0..<rect.w {
                let x = rect.x + xx, y = rect.y + yy
                var keep: Double
                if antiAlias {
                    // 3x3 average of the erase mask: interior pixels go fully clear, edge pixels partly.
                    var s = 0, n = 0
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let nx = x + dx, ny = y + dy
                            if nx >= 0 && ny >= 0 && nx < w && ny < h {
                                s += Int(mask[ny * w + nx])
                                n += 1
                            }
                        }
                    }
                    let m = Double(s) / Double(n * 255)
                    keep = mask[y * w + x] != 0 ? max(0, 1 - m * 1.5) : 1 - m * 0.5
                    if mask[y * w + x] != 0 && m > 0.99 { keep = 0 }
                } else {
                    keep = mask[y * w + x] != 0 ? 0 : 1
                }
                if keep < 1 {
                    let o = (yy * rect.w + xx) * 4
                    for c in 0..<4 { out[o + c] = UInt8((Double(out[o + c]) * keep).rounded()) }
                }
            }
        }
        return MagicEraseResult(rect: rect, pixels: out, erasedCount: count)
    }
}
