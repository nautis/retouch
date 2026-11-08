import Foundation

/// Content-aware fill for the spot healing brush.
///
/// Method: multi-scale PatchMatch image completion (Wexler et al. 2007, with Barnes et al. 2009's
/// PatchMatch for the nearest-neighbour search). The painted area is filled coarse-to-fine; at each
/// scale every 7x7 patch touching the hole is matched to the most similar patch outside it, and each
/// hole pixel becomes a similarity-weighted vote of the patches that cover it.
public enum Inpainter {
    static let r = 3 // patch radius: 7x7 patches


    /// Returns the healed bytes for `mask.rect` (only masked pixels differ from the input).
    public static func heal(_ buffer: PixelBuffer, mask: HealMask) -> [UInt8] {
        let hr = mask.rect
        // Nothing painted: the patch field would have no targets to vote with.
        guard mask.bits.contains(where: { $0 != 0 }) else { return buffer.copyRegion(hr) }
        let maxDim = max(hr.w, hr.h)
        let margin = min(max(Int(Double(maxDim) * 0.75), 6 * r + 10), 400)
        let cr = hr.expanded(by: margin).intersection(buffer.bounds)
        let W = cr.w, H = cr.h

        var img = [Float](repeating: 0, count: W * H * 4)
        var hole = [Bool](repeating: false, count: W * H)
        buffer.pixels.withUnsafeBufferPointer { p in
            for y in 0..<H {
                for x in 0..<W {
                    let s = ((cr.y + y) * buffer.width + cr.x + x) * 4
                    let d = (y * W + x) * 4
                    img[d] = Float(p[s]); img[d + 1] = Float(p[s + 1])
                    img[d + 2] = Float(p[s + 2]); img[d + 3] = Float(p[s + 3])
                }
            }
        }
        for y in 0..<hr.h {
            for x in 0..<hr.w where mask.bits[y * hr.w + x] != 0 {
                hole[(y + hr.y - cr.y) * W + (x + hr.x - cr.x)] = true
            }
        }

        var filled = complete(image: img, hole: hole, width: W, height: H)
        restoreGrain(&filled, hole: hole, w: W, h: H)

        var out = buffer.copyRegion(hr)
        for y in 0..<hr.h {
            for x in 0..<hr.w where mask.bits[y * hr.w + x] != 0 {
                let s = ((y + hr.y - cr.y) * W + (x + hr.x - cr.x)) * 4
                let d = (y * hr.w + x) * 4
                for c in 0..<4 { out[d + c] = UInt8(min(255, max(0, filled[s + c].rounded()))) }
                // keep premultiplied color valid
                for c in 0..<3 where out[d + c] > out[d + 3] { out[d + c] = out[d + 3] }
            }
        }
        return out
    }

    // MARK: - Grain

    /// Patch matching against a smooth estimate favours smooth sources, so fills come out quieter than
    /// the photo around them. The fill and a ring of real pixels around it are split into four detail
    /// bands (fine grain up to blotches ~20 px across). Wherever the fill has less energy in a band than
    /// the ring, real detail from a nearby clean block of the same shape is added, scaled to match.
    static func restoreGrain(_ est: inout [Float], hole: [Bool], w: Int, h: Int) {
        let footprint = 12
        let near = dilate(hole, w: w, h: h, by: footprint)
        let holeIdx = (0..<(w * h)).filter { hole[$0] }
        guard !holeIdx.isEmpty else { return }
        var minX = w, minY = h, maxX = -1, maxY = -1
        for i in holeIdx {
            let x = i % w, y = i / w
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
        let bw = maxX - minX + 1, bh = maxY - minY + 1
        let far = dilate(hole, w: w, h: h, by: footprint + max(12, max(bw, bh) / 2))

        // Nearest offset that moves the whole hole onto real pixels, clear of the hole's blur footprint.
        var best: (Int, Int)? = nil
        var radius = max(bw, bh) / 2 + footprint
        search: while radius < max(w, h) {
            let step = max(2, radius / 8)
            for dy in stride(from: -radius, through: radius, by: step) {
                for dx in stride(from: -radius, through: radius, by: step) {
                    guard max(abs(dx), abs(dy)) >= radius - step else { continue }
                    guard minX + dx >= 0, minY + dy >= 0, maxX + dx < w, maxY + dy < h else { continue }
                    var ok = true
                    for i in holeIdx where near[(i / w + dy) * w + (i % w + dx)] { ok = false; break }
                    if ok { best = (dx, dy); break search }
                }
            }
            radius += max(4, radius / 3)
        }
        guard let (ox, oy) = best else { return }

        // Gaussian-ish pyramid of the filled image: G0 = est, G1..G4 progressively blurrier.
        let g1 = blur5(est, w: w, h: h)
        let g2 = boxBlur3(est, w: w, h: h, radius: 2)
        let g3 = boxBlur3(est, w: w, h: h, radius: 5)
        let g4 = boxBlur3(est, w: w, h: h, radius: 10)
        // (band, sigma of its lower edge). A band is only topped up when the hole is at least 3 sigma
        // thick: thin strokes get their coarse detail from the patches along their edges, and adding
        // coarse detail there pastes unrelated structure (stitching, edges) into the fill.
        let bands: [([Float], [Float], Double)] = [(est, g1, 1.0), (g1, g2, 2.4), (g2, g3, 5.5), (g3, g4, 10.5)]
        let thickness = inradius(hole, w: w, h: h, cap: 40)

        var add = [Float](repeating: 0, count: holeIdx.count * 3)
        for (hi, lo, sigma) in bands where Double(thickness) >= 3 * sigma {
            var ringE = 0.0, ringN = 0.0, fillE = 0.0, srcE = 0.0
            for i in 0..<(w * h) where far[i] && !near[i] {
                for c in 0..<3 { let d = Double(hi[i * 4 + c] - lo[i * 4 + c]); ringE += d * d }
                ringN += 3
            }
            for i in holeIdx {
                let j = (i / w + oy) * w + (i % w + ox)
                for c in 0..<3 {
                    let f = Double(hi[i * 4 + c] - lo[i * 4 + c]); fillE += f * f
                    let s = Double(hi[j * 4 + c] - lo[j * 4 + c]); srcE += s * s
                }
            }
            let n = Double(holeIdx.count * 3)
            guard ringN > 0, srcE > 1e-6 else { continue }
            let ringVar = ringE / ringN, fillVar = fillE / n, srcVar = srcE / n
            guard ringVar > fillVar * 1.05 else { continue }
            let k = Float(min(1.0, sqrt((ringVar - fillVar) / srcVar)))
            for (m, i) in holeIdx.enumerated() {
                let j = (i / w + oy) * w + (i % w + ox)
                for c in 0..<3 { add[m * 3 + c] += k * (hi[j * 4 + c] - lo[j * 4 + c]) }
            }
        }
        for (m, i) in holeIdx.enumerated() {
            for c in 0..<3 { est[i * 4 + c] += add[m * 3 + c] }
        }
    }

    /// Largest Chebyshev distance from a hole pixel to the nearest real pixel (half the stroke width).
    static func inradius(_ hole: [Bool], w: Int, h: Int, cap: Int) -> Int {
        var outside = hole.map { !$0 }
        for d in 1...cap {
            outside = dilate(outside, w: w, h: h, by: 1)
            if !zip(hole, outside).contains(where: { $0 && !$1 }) { return d }
        }
        return cap
    }

    /// Three passes of a separable box blur (approximates a Gaussian with sigma ~ radius).
    static func boxBlur3(_ src: [Float], w: Int, h: Int, radius r: Int) -> [Float] {
        var a = src
        var b = [Float](repeating: 0, count: src.count)
        for _ in 0..<3 {
            for y in 0..<h {
                for c in 0..<4 {
                    var sum: Float = 0
                    for t in -r...r { sum += a[(y * w + min(max(t, 0), w - 1)) * 4 + c] }
                    for x in 0..<w {
                        b[(y * w + x) * 4 + c] = sum / Float(2 * r + 1)
                        let addX = min(x + r + 1, w - 1), subX = max(x - r, 0)
                        sum += a[(y * w + addX) * 4 + c] - a[(y * w + subX) * 4 + c]
                    }
                }
            }
            for x in 0..<w {
                for c in 0..<4 {
                    var sum: Float = 0
                    for t in -r...r { sum += b[(min(max(t, 0), h - 1) * w + x) * 4 + c] }
                    for y in 0..<h {
                        a[(y * w + x) * 4 + c] = sum / Float(2 * r + 1)
                        let addY = min(y + r + 1, h - 1), subY = max(y - r, 0)
                        sum += b[(addY * w + x) * 4 + c] - b[(subY * w + x) * 4 + c]
                    }
                }
            }
        }
        return a
    }

    static func dilate(_ m: [Bool], w: Int, h: Int, by d: Int) -> [Bool] {
        // separable square dilation
        var tmp = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            var last = -1_000_000
            for x in 0..<w { if m[y * w + x] { last = x }; if x - last <= d { tmp[y * w + x] = true } }
            last = 1_000_000
            for x in stride(from: w - 1, through: 0, by: -1) { if m[y * w + x] { last = x }; if last - x <= d { tmp[y * w + x] = true } }
        }
        var out = [Bool](repeating: false, count: w * h)
        for x in 0..<w {
            var last = -1_000_000
            for y in 0..<h { if tmp[y * w + x] { last = y }; if y - last <= d { out[y * w + x] = true } }
            last = 1_000_000
            for y in stride(from: h - 1, through: 0, by: -1) { if tmp[y * w + x] { last = y }; if last - y <= d { out[y * w + x] = true } }
        }
        return out
    }

    /// Separable 5-tap binomial blur, edge-clamped, 4 channels.
    static func blur5(_ src: [Float], w: Int, h: Int) -> [Float] {
        let k: [Float] = [1, 4, 6, 4, 1].map { $0 / 16 }
        var tmp = [Float](repeating: 0, count: src.count)
        for y in 0..<h {
            for x in 0..<w {
                for c in 0..<4 {
                    var s: Float = 0
                    for t in -2...2 { s += k[t + 2] * src[(y * w + min(max(x + t, 0), w - 1)) * 4 + c] }
                    tmp[(y * w + x) * 4 + c] = s
                }
            }
        }
        var out = [Float](repeating: 0, count: src.count)
        for y in 0..<h {
            for x in 0..<w {
                for c in 0..<4 {
                    var s: Float = 0
                    for t in -2...2 { s += k[t + 2] * tmp[(min(max(y + t, 0), h - 1) * w + x) * 4 + c] }
                    out[(y * w + x) * 4 + c] = s
                }
            }
        }
        return out
    }

    // MARK: - Multi-scale completion


    static func complete(image: [Float], hole: [Bool], width: Int, height: Int) -> [Float] {
        var levels = [PyramidLevel(img: image, hole: hole, w: width, h: height)]
        let p = 2 * r + 1
        while true {
            let L = levels.last!
            let ext = holeExtent(L)
            if ext <= p || min(L.w, L.h) / 2 < 4 * p { break }
            levels.append(downsample(L))
        }

        var rng = XorShift(seed: 0x9E37_79B9_7F4A_7C15)
        var cur = levels.count - 1
        var est = levels[cur].img
        diffusionFill(&est, hole: levels[cur].hole, w: levels[cur].w, h: levels[cur].h)
        var nnf: PatchField? = nil

        while cur >= 0 {
            let L = levels[cur]
            if cur < levels.count - 1 {
                let C = levels[cur + 1]
                est = upsampleEstimate(fine: L, coarse: est, cw: C.w, ch: C.h)
            }
            let fromCoarsest = levels.count - 1 - cur
            let emIters = fromCoarsest == 0 ? 8 : max(2, 5 - fromCoarsest)
            let pmIters = fromCoarsest == 0 ? 5 : 3

            guard var field = PatchField(level: L, previous: nnf, rng: &rng, est: est) else {
                // No usable source area at this scale: keep the smooth fill.
                if cur == 0 { return est }
                cur -= 1
                continue
            }
            for em in 0..<emIters {
                if em > 0 { field.recomputeDistances(est: est) }
                field.search(est: est, iterations: pmIters, rng: &rng)
                field.vote(into: &est)
            }
            if cur == 0 {
                // Voting averages overlapping patches, which washes out film grain and fine texture.
                // Finish by copying each hole pixel straight from its own best match.
                field.recomputeDistances(est: est)
                field.search(est: est, iterations: 2, rng: &rng)
                field.copyCenters(into: &est)
            }
            nnf = field
            cur -= 1
        }
        return est
    }

    static func holeExtent(_ L: PyramidLevel) -> Int {
        var minX = L.w, minY = L.h, maxX = -1, maxY = -1
        for y in 0..<L.h {
            for x in 0..<L.w where L.hole[y * L.w + x] {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return maxX < 0 ? 0 : max(maxX - minX + 1, maxY - minY + 1)
    }

    /// 2x box downsample. A coarse pixel is hole if any of its four fine pixels is hole,
    /// so coarse known pixels average only real data.
    static func downsample(_ L: PyramidLevel) -> PyramidLevel {
        let w2 = (L.w + 1) / 2, h2 = (L.h + 1) / 2
        var img = [Float](repeating: 0, count: w2 * h2 * 4)
        var hole = [Bool](repeating: false, count: w2 * h2)
        for y in 0..<h2 {
            for x in 0..<w2 {
                var acc: (Float, Float, Float, Float) = (0, 0, 0, 0)
                var n: Float = 0
                var anyHole = false
                for dy in 0..<2 {
                    for dx in 0..<2 {
                        let fx = 2 * x + dx, fy = 2 * y + dy
                        guard fx < L.w, fy < L.h else { continue }
                        let i = fy * L.w + fx
                        if L.hole[i] { anyHole = true; continue }
                        acc.0 += L.img[i * 4]; acc.1 += L.img[i * 4 + 1]
                        acc.2 += L.img[i * 4 + 2]; acc.3 += L.img[i * 4 + 3]
                        n += 1
                    }
                }
                let o = y * w2 + x
                hole[o] = anyHole
                if n > 0 {
                    img[o * 4] = acc.0 / n; img[o * 4 + 1] = acc.1 / n
                    img[o * 4 + 2] = acc.2 / n; img[o * 4 + 3] = acc.3 / n
                }
            }
        }
        return PyramidLevel(img: img, hole: hole, w: w2, h: h2)
    }

    /// Onion-peel fill from the boundary inward, then smoothing. Used once, at the coarsest scale.
    static func diffusionFill(_ img: inout [Float], hole: [Bool], w: Int, h: Int) {
        var known = hole.map { !$0 }
        var remaining = hole.filter { $0 }.count
        while remaining > 0 {
            var updates: [(Int, (Float, Float, Float, Float))] = []
            for y in 0..<h {
                for x in 0..<w where !known[y * w + x] {
                    var acc: (Float, Float, Float, Float) = (0, 0, 0, 0)
                    var n: Float = 0
                    for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)] {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < w, ny < h, known[ny * w + nx] else { continue }
                        let j = (ny * w + nx) * 4
                        acc.0 += img[j]; acc.1 += img[j + 1]; acc.2 += img[j + 2]; acc.3 += img[j + 3]
                        n += 1
                    }
                    if n > 0 { updates.append((y * w + x, (acc.0 / n, acc.1 / n, acc.2 / n, acc.3 / n))) }
                }
            }
            if updates.isEmpty { break } // hole with no known pixels at all
            for (i, v) in updates {
                img[i * 4] = v.0; img[i * 4 + 1] = v.1; img[i * 4 + 2] = v.2; img[i * 4 + 3] = v.3
                known[i] = true
            }
            remaining -= updates.count
        }
        for _ in 0..<20 {
            for y in 0..<h {
                for x in 0..<w where hole[y * w + x] {
                    var acc: (Float, Float, Float, Float) = (0, 0, 0, 0)
                    var n: Float = 0
                    for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                        let j = (ny * w + nx) * 4
                        acc.0 += img[j]; acc.1 += img[j + 1]; acc.2 += img[j + 2]; acc.3 += img[j + 3]
                        n += 1
                    }
                    let i = (y * w + x) * 4
                    img[i] = acc.0 / n; img[i + 1] = acc.1 / n; img[i + 2] = acc.2 / n; img[i + 3] = acc.3 / n
                }
            }
        }
    }

    /// Fine-level estimate: real pixels where known, bilinear from the coarse result inside the hole.
    static func upsampleEstimate(fine L: PyramidLevel, coarse: [Float], cw: Int, ch: Int) -> [Float] {
        var est = L.img
        for y in 0..<L.h {
            for x in 0..<L.w where L.hole[y * L.w + x] {
                let fx = min(max((Double(x) + 0.5) / 2 - 0.5, 0), Double(cw - 1))
                let fy = min(max((Double(y) + 0.5) / 2 - 0.5, 0), Double(ch - 1))
                let x0 = Int(fx), y0 = Int(fy)
                let x1 = min(x0 + 1, cw - 1), y1 = min(y0 + 1, ch - 1)
                let ax = Float(fx - Double(x0)), ay = Float(fy - Double(y0))
                let i = (y * L.w + x) * 4
                for c in 0..<4 {
                    let v00 = coarse[(y0 * cw + x0) * 4 + c], v10 = coarse[(y0 * cw + x1) * 4 + c]
                    let v01 = coarse[(y1 * cw + x0) * 4 + c], v11 = coarse[(y1 * cw + x1) * 4 + c]
                    est[i + c] = (v00 * (1 - ax) + v10 * ax) * (1 - ay) + (v01 * (1 - ax) + v11 * ax) * ay
                }
            }
        }
        return est
    }

}
