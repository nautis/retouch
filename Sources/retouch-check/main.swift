import CoreImage
import Foundation
import ImageIO
import RetouchCore

// Engine checks on a real photo. Usage: retouch-check <image> <output dir>
// A raw file goes through the develop checks; JPG, PNG, HEIC and TIFF skip them. Every check
// prints PASS/FAIL; image outputs are written for visual inspection. Positions are fractions of
// the image, so any photo of at least 400x300 works (timings mean more on a big one).

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: retouch-check <raw-or-image> <outdir>")
    exit(2)
}
let input = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let ctx = RetouchContext.shared
var failures = 0

@MainActor func check(_ ok: Bool, _ what: String) {
    print(ok ? "PASS" : "FAIL", what)
    if !ok { failures += 1 }
}

@MainActor func timed<T>(_ label: String, _ f: () throws -> T) rethrows -> T {
    let t0 = Date.now
    let v = try f()
    print("  \(label): \(Date.now.timeIntervalSince(t0).formatted(.number.precision(.fractionLength(2))))s")
    return v
}

@MainActor func save(_ b: PixelBuffer, _ name: String, maxSide: Int? = nil) {
    var w = b.width, h = b.height
    if let m = maxSide, max(w, h) > m {
        let s = Double(m) / Double(max(w, h))
        w = max(1, Int(Double(w) * s)); h = max(1, Int(Double(h) * s))
    }
    let fmt: ExportFormat = name.hasSuffix(".png") ? .png : .jpeg
    try! ImageFiles.export(b, to: outDir.appendingPathComponent(name),
                           options: .init(format: fmt, quality: 0.92, width: w, height: h))
}

// 1. Open: raw develop, or a plain raster load
let isRaw = ImageFiles.isRaw(input)
let photo: PixelBuffer
if isRaw {
    let info = try ImageFiles.rawInfo(input)
    print("  raw \(info.width)x\(info.height), lens correction supported: \(info.lensCorrectionSupported)")
    photo = try timed("full-res develop (standard)") {
        try ImageFiles.developRaw(input, settings: RawSettings(look: .standard, lensCorrection: true))
    }
    check(photo.width == info.width && photo.height == info.height, "full-res develop is \(photo.width)x\(photo.height)")
    check(!photo.hasTransparency, "developed raw is opaque")
    for look in RawLook.allCases {
        let p = try timed("preview develop \(look.rawValue) @1600") {
            try ImageFiles.developRaw(input, settings: RawSettings(look: look), maxDimension: 1600)
        }
        save(p, "look-\(look.rawValue).jpg")
    }
} else {
    photo = try timed("open \(input.lastPathComponent)") { try ImageFiles.loadRaster(input) }
    check(photo.width > 0 && photo.height > 0, "opened \(photo.width)x\(photo.height)")
}
let W = photo.width, H = photo.height
guard W >= 400, H >= 300 else {
    print("image is \(W)x\(H); the checks need at least 400x300")
    exit(2)
}
let cx = Double(W) / 2, cy = Double(H) / 2

/// Pixel position at a fraction of the width or height.
@MainActor func fx(_ f: Double) -> Int { Int(Double(W) * f) }
@MainActor func fy(_ f: Double) -> Int { Int(Double(H) * f) }
/// A rect of up to `w` x `h` pixels with its top-left at the given fractions, kept inside the image.
@MainActor func rectAt(_ x: Double, _ y: Double, w: Int, h: Int) -> IRect {
    IRect(x: fx(x), y: fy(y), w: min(w, W - fx(x)), h: min(h, H - fy(y)))
}

// 2. Buffer <-> Core Image round trip keeps orientation and values
do {
    let r = rectAt(0.12, 0.13, w: 300, h: 200)
    let crop = photo.cropped(r)
    let back = PixelBuffer.render(crop.ciImage(), width: crop.width, height: crop.height, context: ctx)
    var maxDiff = 0
    for i in 0..<crop.pixels.count { maxDiff = max(maxDiff, abs(Int(crop.pixels[i]) - Int(back.pixels[i]))) }
    check(maxDiff <= 1, "CIImage round trip max channel diff \(maxDiff) (<=1)")
    var region = photo.renderRegion(photo.ciImage(), rect: r, context: ctx)
    var regDiff = 0
    for i in 0..<region.count { regDiff = max(regDiff, abs(Int(region[i]) - Int(crop.pixels[i]))) }
    check(regDiff <= 1, "renderRegion lands on the same top-left rect (diff \(regDiff))")
    region.removeAll()
}

// 3. Healing: paint fake defects onto real texture, heal, measure how close the fill is to the original
@MainActor func healTest(name: String, stroke: [ImagePoint], diameter: Double) {
    var b = photo
    guard let mask = HealMask.stroke(points: stroke, diameter: diameter, imageBounds: b.bounds) else {
        check(false, "\(name): mask"); return
    }
    let original = b.copyRegion(mask.rect)
    // defect: saturated magenta inside the mask
    var defect = original
    for i in 0..<mask.bits.count where mask.bits[i] != 0 {
        defect[i * 4] = 255; defect[i * 4 + 1] = 0; defect[i * 4 + 2] = 255; defect[i * 4 + 3] = 255
    }
    b.writeRegion(mask.rect, defect)
    let ctxRect = mask.rect.expanded(by: Int(diameter * 2.5)).intersection(b.bounds)
    let before = b.cropped(ctxRect)
    let healed = timed("\(name) heal (\(mask.rect.w)x\(mask.rect.h) px mask)") { Inpainter.heal(b, mask: mask) }
    // Error vs. the real pixels that were under the defect
    var se = 0.0, n = 0.0, magenta = 0
    for i in 0..<mask.bits.count where mask.bits[i] != 0 {
        for c in 0..<3 {
            let d = Double(healed[i * 4 + c]) - Double(original[i * 4 + c])
            se += d * d
            n += 1
        }
        if healed[i * 4] > 220 && healed[i * 4 + 1] < 40 && healed[i * 4 + 2] > 220 { magenta += 1 }
    }
    let rmse = sqrt(se / n)
    // Pixels outside the mask must be untouched
    var outsideChanged = 0
    for i in 0..<mask.bits.count where mask.bits[i] == 0 {
        for c in 0..<4 where healed[i * 4 + c] != defect[i * 4 + c] { outsideChanged += 1 }
    }
    check(magenta == 0, "\(name): no defect color left (\(magenta) px)")
    check(outsideChanged == 0, "\(name): pixels outside the brush untouched")
    print("  \(name): RMSE vs. true pixels \(rmse.formatted(.number.precision(.fractionLength(1)))) levels")
    b.writeRegion(mask.rect, healed)
    let after = b.cropped(ctxRect)
    save(before, "heal-\(name)-before.png")
    save(after, "heal-\(name)-after.png")
    let truth = photo.cropped(ctxRect)
    save(truth, "heal-\(name)-truth.png")
}

let unit = Double(W) / 8192 // brush sizes scale with the image; the reference sizes are for a 45 MP frame
// a spot above and right of the center
healTest(name: "spot", stroke: [ImagePoint(x: cx + 0.085 * Double(W), y: cy - 0.165 * Double(H))], diameter: max(6, 40 * unit))
// a long shallow diagonal scratch, lower left
healTest(name: "scratch",
         stroke: (0...20).map { ImagePoint(x: cx - 0.27 * Double(W) + Double($0) * 25 * unit, y: cy + 0.22 * Double(H) + Double($0) * 6 * unit) },
         diameter: max(5, 24 * unit))
// a short horizontal stroke: edges that cross it should continue through the fill
healTest(name: "line", stroke: [ImagePoint(x: 0.28 * Double(W), y: 0.48 * Double(H)), ImagePoint(x: 0.30 * Double(W), y: 0.48 * Double(H))],
         diameter: max(6, 30 * unit))
// a large blob near the top-left corner
healTest(name: "blob",
         stroke: (0...10).map { ImagePoint(x: 0.073 * Double(W) + Double($0) * 20 * unit, y: 0.11 * Double(H) + Double($0) * 12 * unit) },
         diameter: max(12, 120 * unit))

// 4. Magic eraser on a synthetic image: gray background, dark disc
do {
    var s = PixelBuffer(width: 400, height: 300, fill: (200, 200, 200, 255))
    for y in 0..<300 {
        for x in 0..<400 where (x - 200) * (x - 200) + (y - 150) * (y - 150) < 80 * 80 {
            let i = (y * 400 + x) * 4
            s.pixels[i] = 30; s.pixels[i + 1] = 40; s.pixels[i + 2] = 50
        }
    }
    let res = MagicEraser.erase(s, x: 5, y: 5, tolerance: 32, contiguous: true, antiAlias: false)!
    s.writeRegion(res.rect, res.pixels)
    let center = (150 * 400 + 200) * 4
    check(s.pixels[3] == 0, "magic eraser: clicked background is transparent")
    check(s.pixels[center + 3] == 255, "magic eraser: disc kept")
    let expected = 400 * 300 - Int(Double.pi * 80 * 80)
    check(abs(res.erasedCount - expected) < 400, "magic eraser: erased \(res.erasedCount) px (expected ~\(expected))")
    save(s, "magic-eraser-synthetic.png")
    // Contiguous on the real photo, clicking near its top-left corner
    var p = photo.cropped(IRect(x: 0, y: 0, w: min(2000, W), h: min(1400, H)))
    if let r2 = timed("magic eraser contiguous on \(p.width)x\(p.height) photo crop", {
        MagicEraser.erase(p, x: p.width * 3 / 20, y: p.height * 3 / 14, tolerance: 32, contiguous: true, antiAlias: true)
    }) {
        p.writeRegion(r2.rect, r2.pixels)
        print("  erased \(r2.erasedCount) px on photo crop")
    }
    save(p, "magic-eraser-photo.png", maxSide: 1200)
}

// 5. Filters inside a selection: outside untouched, alpha stays opaque
let selW = min(1200, W / 2), selH = min(800, H / 2)
let sel = IRect(x: Int(cx) - selW / 2, y: Int(cy) - selH / 2, w: selW, h: selH)
let ops: [FilterOp] = [
    .unsharpMask(amount: 150, radius: 2, threshold: 0),
    .unsharpMask(amount: 150, radius: 2, threshold: 8),
    .sharpen, .mosaic(cellSize: 40), .crystallize(cellSize: 40), .pointillize(cellSize: 30),
    .hueSaturation(hue: 40, saturation: 30, lightness: 0),
    .hueSaturation(hue: 0, saturation: 0, lightness: 40),
]
for op in ops {
    let bytes = timed("\(op) on \(sel.w)x\(sel.h) selection") { Filters.apply(op, to: photo, rect: sel) }
    var opaque = true
    var changed = 0
    let orig = photo.copyRegion(sel)
    for i in stride(from: 0, to: bytes.count, by: 4) {
        if bytes[i + 3] != 255 { opaque = false }
        if bytes[i] != orig[i] || bytes[i + 1] != orig[i + 1] || bytes[i + 2] != orig[i + 2] { changed += 1 }
    }
    check(opaque, "\(op.historyName): result opaque")
    check(changed > sel.area / 20, "\(op.historyName): changed \(changed) of \(sel.area) px")
    var shown = photo
    shown.writeRegion(sel, bytes)
    let name = "\(op)".replacing(/[^A-Za-z0-9]+/, with: "-")
    save(shown.cropped(sel.expanded(by: 100).intersection(photo.bounds)), "filter-\(name).jpg", maxSide: 1400)
}
// full-image unsharp timing (no selection)
_ = timed("unsharp mask, whole \(W)x\(H) image") {
    Filters.apply(.unsharpMask(amount: 100, radius: 1.5, threshold: 0), to: photo, rect: photo.bounds)
}

// 6. Auto Tone / Contrast / Color
var flat: PixelBuffer
if isRaw {
    flat = try ImageFiles.developRaw(input, settings: RawSettings(look: .flat), maxDimension: 1600)
} else {
    let s = min(1.0, 1600 / Double(max(W, H)))
    flat = Transforms.resize(photo, width: max(1, Int(Double(W) * s)), height: max(1, Int(Double(H) * s)))
}
save(flat, "auto-0-input.jpg")
for k in AutoAdjust.allCases {
    let bytes = timed(k.historyName) { k.apply(to: flat, rect: flat.bounds) }
    var b = flat
    b.writeRegion(flat.bounds, bytes)
    save(b, "auto-\(k.rawValue).jpg")
    var lo = 255, hi = 0
    for i in stride(from: 0, to: bytes.count, by: 4) {
        let l = (Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2])) / 3
        lo = min(lo, l); hi = max(hi, l)
    }
    check(hi - lo > 200, "\(k.historyName): tonal range \(lo)...\(hi)")
}
// A photo may already reach 0 and 255, so squeeze a central crop into 70...180 and confirm each
// auto command stretches it back out.
do {
    var squeezed = photo.cropped(IRect(x: Int(cx) - fx(0.15), y: Int(cy) - fy(0.15), w: fx(0.3), h: fy(0.3)))
    for i in 0..<squeezed.pixels.count where i % 4 != 3 {
        squeezed.pixels[i] = UInt8(70 + Int(squeezed.pixels[i]) * 110 / 255)
    }
    save(squeezed, "auto-1-squeezed-input.jpg", maxSide: 1200)
    for k in AutoAdjust.allCases {
        let bytes = k.apply(to: squeezed, rect: squeezed.bounds)
        var lo = [255, 255, 255], hi = [0, 0, 0]
        for i in stride(from: 0, to: bytes.count, by: 4) {
            for c in 0..<3 { lo[c] = min(lo[c], Int(bytes[i + c])); hi[c] = max(hi[c], Int(bytes[i + c])) }
        }
        check(lo.allSatisfy { $0 <= 5 } && hi.allSatisfy { $0 >= 250 },
              "\(k.historyName) stretches a 70...180 image to \(lo)...\(hi)")
        var b = squeezed
        b.writeRegion(squeezed.bounds, bytes)
        save(b, "auto-1-squeezed-\(k.rawValue).jpg", maxSide: 1200)
    }
}
_ = timed("Auto Tone, whole \(W)x\(H) image") { AutoAdjust.tone.apply(to: photo, rect: photo.bounds) }
flat.pixels.removeAll()

// 7. Geometry
let small = photo.cropped(IRect(x: 0, y: 0, w: min(1600, W), h: min(1000, H)))
let cw = small.rotated90(clockwise: true)
check(cw.width == small.height && cw.height == small.width, "rotate 90 CW dims")
// top-left pixel of the original must land at top-right after a clockwise turn
let tl = Array(small.pixels[0..<4]), trIdx = (0 * cw.width + cw.width - 1) * 4
check(Array(cw.pixels[trIdx..<trIdx + 4]) == tl, "rotate 90 CW moves top-left to top-right")
check(cw.rotated90(clockwise: false).pixels == small.pixels, "rotate CW then CCW is identity")
check(small.rotated180().rotated180().pixels == small.pixels, "rotate 180 twice is identity")
let arb = timed("arbitrary rotate 5 deg (\(small.width)x\(small.height))") { Transforms.rotate(small, degrees: 5) }
check(arb.width > small.width && arb.height > small.height, "arbitrary rotate grows canvas to \(arb.width)x\(arb.height)")
check(arb.pixels[3] == 0, "arbitrary rotate: new corner is transparent")
save(arb, "rotate-5deg.png", maxSide: 1200)
let rw = min(1600, W), rh = max(1, Int((Double(rw) * Double(H) / Double(W)).rounded()))
let resized = timed("resize \(W) -> \(rw) wide") { Transforms.resize(photo, width: rw, height: rh) }
check(resized.width == rw && resized.height == rh && !resized.hasTransparency, "resize to exactly \(rw)x\(rh), opaque")
save(resized, "resize-\(rw).jpg")
let up = Transforms.resize(small, width: small.width * 2, height: small.height * 2)
check(up.width == small.width * 2 && up.height == small.height * 2, "upscale to \(up.width)x\(up.height)")

// 8. Export: JPG full size, PNG with transparency, sRGB conversion
do {
    let jpgURL = outDir.appendingPathComponent("export-full.jpg")
    try timed("export full-res JPG") {
        try ImageFiles.export(photo, to: jpgURL, options: .init(format: .jpeg, quality: 0.9, width: photo.width, height: photo.height))
    }
    let src = CGImageSourceCreateWithURL(jpgURL as CFURL, nil)!
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [String: Any]
    let pw = props[kCGImagePropertyPixelWidth as String] as? Int ?? 0
    let ph = props[kCGImagePropertyPixelHeight as String] as? Int ?? 0
    let profile = props[kCGImagePropertyProfileName as String] as? String ?? "none"
    check(pw == photo.width && ph == photo.height, "exported JPG is \(pw)x\(ph)")
    check(profile.lowercased().contains("srgb"), "exported JPG profile: \(profile)")
    let pngURL = outDir.appendingPathComponent("export-transparent.png")
    try ImageFiles.export(arb, to: pngURL, options: .init(format: .png, width: arb.width, height: arb.height))
    let back = try ImageFiles.loadRaster(pngURL)
    check(back.pixels[3] == 0 && back.width == arb.width, "PNG keeps transparency (\(back.width)x\(back.height))")
    let reread = try ImageFiles.loadRaster(jpgURL)
    check(reread.width == photo.width, "exported JPG reopens (\(reread.width)x\(reread.height))")
}

// 9. History
do {
    var b = small
    let h = History()
    let r = IRect(x: 10, y: 10, w: 50, h: 40)
    h.applyRegion("Test", rect: r, after: [UInt8](repeating: 7, count: r.area * 4), to: &b)
    h.applyWhole("Crop", newBuffer: b.cropped(IRect(x: 0, y: 0, w: 100, h: 100)), to: &b)
    check(b.width == 100, "history: crop applied")
    h.undo(&b)
    h.undo(&b)
    check(b.pixels == small.pixels, "history: two undos restore the original exactly")
    h.redo(&b)
    h.redo(&b)
    check(b.width == 100 && b.pixels[(10 * 100 + 10) * 4] == 7, "history: two redos reapply both edits")
}

print(failures == 0 ? "\nALL CHECKS PASSED" : "\n\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
