import Foundation

/// Patch radius shared with Inpainter (7x7 patches).
private let r = Inpainter.r

/// PatchMatch nearest-neighbour field: for every patch touching the hole, the best-matching
/// patch centre outside it, plus the match distance.
struct PatchField {
    let w: Int
    let h: Int
    let hole: [Bool]
    let isTarget: [Bool]
    let validSource: [Bool]
    let targets: [Int32]
    let sources: [Int32]
    var sx: [Int32]
    var sy: [Int32]
    var dist: [Float]

    init?(level L: PyramidLevel, previous: PatchField?, rng: inout XorShift, est: [Float]) {
        w = L.w
        h = L.h
        hole = L.hole
        // Dilate the hole by the patch radius: target centers touch the hole,
        // source centers must keep their whole patch out of it.
        var dil = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w where L.hole[y * w + x] {
                for yy in max(0, y - r)...min(h - 1, y + r) {
                    for xx in max(0, x - r)...min(w - 1, x + r) { dil[yy * w + xx] = true }
                }
            }
        }
        isTarget = dil
        var vs = [Bool](repeating: false, count: w * h)
        var srcList: [Int32] = []
        if w > 2 * r && h > 2 * r {
            for y in r..<(h - r) {
                for x in r..<(w - r) where !dil[y * w + x] {
                    vs[y * w + x] = true
                    srcList.append(Int32(y * w + x))
                }
            }
        }
        guard !srcList.isEmpty else { return nil }
        validSource = vs
        sources = srcList
        var tl: [Int32] = []
        for i in 0..<(w * h) where dil[i] { tl.append(Int32(i)) }
        targets = tl
        sx = [Int32](repeating: -1, count: w * h)
        sy = [Int32](repeating: -1, count: w * h)
        dist = [Float](repeating: .greatestFiniteMagnitude, count: w * h)

        for t in tl {
            let ti = Int(t)
            let tx = ti % w, ty = ti / w
            var cx = -1, cy = -1
            if let prev = previous {
                // Upscale the coarse match.
                let px = min(tx / 2, prev.w - 1), py = min(ty / 2, prev.h - 1)
                let pi = py * prev.w + px
                if prev.sx[pi] >= 0 {
                    let ux = 2 * Int(prev.sx[pi]) + (tx - 2 * (tx / 2))
                    let uy = 2 * Int(prev.sy[pi]) + (ty - 2 * (ty / 2))
                    if ux >= 0, uy >= 0, ux < w, uy < h, vs[uy * w + ux] { cx = ux; cy = uy }
                }
            }
            if cx < 0 {
                let s = Int(srcList[rng.next(srcList.count)])
                cx = s % w; cy = s / w
            }
            sx[ti] = Int32(cx)
            sy[ti] = Int32(cy)
        }
        recomputeDistances(est: est)
    }

    mutating func recomputeDistances(est: [Float]) {
        est.withUnsafeBufferPointer { e in
            for t in targets {
                let ti = Int(t)
                dist[ti] = PatchField.patchDistance(e, w, h, ti % w, ti / w, Int(sx[ti]), Int(sy[ti]), .greatestFiniteMagnitude)
            }
        }
    }

    /// Sum of squared differences between the target patch (edge-clamped) and the source patch.
    @inline(__always)
    static func patchDistance(_ e: UnsafeBufferPointer<Float>, _ w: Int, _ h: Int,
                              _ tx: Int, _ ty: Int, _ qx: Int, _ qy: Int, _ best: Float) -> Float {
        var d: Float = 0
        for dy in -r...r {
            let ty2 = min(max(ty + dy, 0), h - 1)
            let qrow = (qy + dy) * w
            let trow = ty2 * w
            for dx in -r...r {
                let tx2 = min(max(tx + dx, 0), w - 1)
                let ti = (trow + tx2) * 4
                let si = (qrow + qx + dx) * 4
                let a = e[ti] - e[si], b = e[ti + 1] - e[si + 1]
                let c = e[ti + 2] - e[si + 2], f = e[ti + 3] - e[si + 3]
                d += a * a + b * b + c * c + f * f
            }
            if d >= best { return d }
        }
        return d
    }

    mutating func search(est: [Float], iterations: Int, rng: inout XorShift) {
        let maxRad = max(w, h)
        est.withUnsafeBufferPointer { e in
            for it in 0..<iterations {
                let forward = it % 2 == 0
                let step = forward ? 1 : -1
                let n = targets.count
                for k in 0..<n {
                    let ti = Int(targets[forward ? k : n - 1 - k])
                    let tx = ti % w, ty = ti / w
                    var bx = Int(sx[ti]), by = Int(sy[ti])
                    var bd = dist[ti]

                    // Propagation from the already-visited neighbours.
                    for (nx, ny) in [(tx - step, ty), (tx, ty - step)] {
                        guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                        let ni = ny * w + nx
                        guard isTarget[ni] else { continue }
                        let cx = Int(sx[ni]) + (tx - nx), cy = Int(sy[ni]) + (ty - ny)
                        guard cx >= 0, cy >= 0, cx < w, cy < h, validSource[cy * w + cx] else { continue }
                        if cx == bx && cy == by { continue }
                        let d = PatchField.patchDistance(e, w, h, tx, ty, cx, cy, bd)
                        if d < bd { bd = d; bx = cx; by = cy }
                    }

                    // Random search in shrinking windows around the current best.
                    var rad = maxRad
                    while rad >= 1 {
                        let cx = min(max(bx + rng.next(2 * rad + 1) - rad, r), w - 1 - r)
                        let cy = min(max(by + rng.next(2 * rad + 1) - rad, r), h - 1 - r)
                        if validSource[cy * w + cx] && !(cx == bx && cy == by) {
                            let d = PatchField.patchDistance(e, w, h, tx, ty, cx, cy, bd)
                            if d < bd { bd = d; bx = cx; by = cy }
                        }
                        rad /= 2
                    }
                    sx[ti] = Int32(bx)
                    sy[ti] = Int32(by)
                    dist[ti] = bd
                }
            }
        }
    }

    /// Each hole pixel takes the exact source pixel its own patch matched (keeps grain and texture).
    func copyCenters(into est: inout [Float]) {
        let snapshot = est
        for i in 0..<(w * h) where hole[i] && sx[i] >= 0 {
            let si = (Int(sy[i]) * w + Int(sx[i])) * 4
            est[i * 4] = snapshot[si]; est[i * 4 + 1] = snapshot[si + 1]
            est[i * 4 + 2] = snapshot[si + 2]; est[i * 4 + 3] = snapshot[si + 3]
        }
    }

    /// Each hole pixel becomes the weighted average of the source pixels that the patches covering
    /// it point to. Weight falls off with patch distance, scaled by the 75th percentile distance.
    func vote(into est: inout [Float]) {
        var ds = targets.map { dist[Int($0)] }
        ds.sort()
        let sigma2 = max(ds[min(ds.count - 1, ds.count * 3 / 4)], 1)
        var acc = [Float](repeating: 0, count: w * h * 4)
        var wsum = [Float](repeating: 0, count: w * h)
        est.withUnsafeBufferPointer { e in
            for t in targets {
                let ti = Int(t)
                let tx = ti % w, ty = ti / w
                let qx = Int(sx[ti]), qy = Int(sy[ti])
                let wgt = max(expf(-dist[ti] / (2 * sigma2)), 1e-6)
                for dy in -r...r {
                    let py = ty + dy
                    guard py >= 0, py < h else { continue }
                    for dx in -r...r {
                        let px = tx + dx
                        guard px >= 0, px < w else { continue }
                        let pi = py * w + px
                        guard hole[pi] else { continue }
                        let si = ((qy + dy) * w + qx + dx) * 4
                        acc[pi * 4] += wgt * e[si]; acc[pi * 4 + 1] += wgt * e[si + 1]
                        acc[pi * 4 + 2] += wgt * e[si + 2]; acc[pi * 4 + 3] += wgt * e[si + 3]
                        wsum[pi] += wgt
                    }
                }
            }
        }
        for i in 0..<(w * h) where hole[i] && wsum[i] > 0 {
            let s = wsum[i]
            est[i * 4] = acc[i * 4] / s; est[i * 4 + 1] = acc[i * 4 + 1] / s
            est[i * 4 + 2] = acc[i * 4 + 2] / s; est[i * 4 + 3] = acc[i * 4 + 3] / s
        }
    }
}
