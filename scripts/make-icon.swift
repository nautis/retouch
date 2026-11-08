import AppKit

// Draws the Retouch app icon (dark rounded square, healing bandage) and writes an .iconset.
// Usage: swift make-icon.swift <out.iconset>
let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = Double(px) / 1024
    // macOS icon grid: 824 pt body inset 100 pt, ~185 pt corner radius
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(red: 0.20, green: 0.22, blue: 0.27, alpha: 1),
                        NSColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)])!.draw(in: shape, angle: -90)
    // soft frame of a "photo" behind the bandage
    let photo = NSBezierPath(roundedRect: body.insetBy(dx: 150 * s, dy: 190 * s), xRadius: 26 * s, yRadius: 26 * s)
    NSGradient(colors: [NSColor(red: 0.95, green: 0.55, blue: 0.30, alpha: 1),
                        NSColor(red: 0.62, green: 0.18, blue: 0.32, alpha: 1)])!.draw(in: photo, angle: -60)
    let config = NSImage.SymbolConfiguration(pointSize: 430 * s, weight: .regular)
        .applying(.init(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "bandage.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let sz = sym.size
        let r = NSRect(x: body.midX - sz.width / 2, y: body.midY - sz.height / 2, width: sz.width, height: sz.height)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 18 * s
        shadow.shadowOffset = NSSize(width: 0, height: -8 * s)
        shadow.set()
        sym.draw(in: r)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
