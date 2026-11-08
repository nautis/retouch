import AppKit

/// The gray checkerboard shown behind transparent pixels.
enum Checkerboard {
    static let color: CGColor = {
        let tile = 8
        let image = NSImage(size: NSSize(width: tile * 2, height: tile * 2), flipped: false) { rect in
            NSColor(white: 0.80, alpha: 1).setFill()
            rect.fill()
            NSColor(white: 0.62, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: tile, height: tile).fill()
            NSRect(x: tile, y: tile, width: tile, height: tile).fill()
            return true
        }
        return NSColor(patternImage: image).cgColor
    }()
}
