import Foundation

/// The pixels a spot-healing stroke covers.
public struct HealMask: Sendable {
    /// Bounding box of the painted pixels, in image coordinates.
    public let rect: IRect
    /// rect.w * rect.h bytes, non-zero = heal this pixel.
    public let bits: [UInt8]

    public init(rect: IRect, bits: [UInt8]) {
        precondition(bits.count == rect.area)
        self.rect = rect
        self.bits = bits
    }

    /// Rasterizes a brush stroke (centers in image pixels) of the given diameter.
    public static func stroke(points: [ImagePoint], diameter: Double, imageBounds: IRect) -> HealMask? {
        guard !points.isEmpty else { return nil }
        let rad = max(0.5, diameter / 2)
        let xs = points.map(\.x), ys = points.map(\.y)
        let box = IRect(
            x: Int(floor(xs.min()! - rad)), y: Int(floor(ys.min()! - rad)),
            w: Int(ceil(xs.max()! + rad)) - Int(floor(xs.min()! - rad)) + 1,
            h: Int(ceil(ys.max()! + rad)) - Int(floor(ys.min()! - rad)) + 1
        ).intersection(imageBounds)
        guard !box.isEmpty else { return nil }
        var bits = [UInt8](repeating: 0, count: box.area)
        let segs: [(ImagePoint, ImagePoint)] = points.count == 1
            ? [(points[0], points[0])]
            : (0..<(points.count - 1)).map { (points[$0], points[$0 + 1]) }
        let r2 = rad * rad
        for (a, b) in segs {
            // Rows and columns this segment can touch, clipped to the box: a stroke that runs off the
            // image has segments entirely outside it, which must be skipped rather than looped over.
            let x0 = max(0, Int(floor(min(a.x, b.x) - rad)) - box.x)
            let x1 = min(box.w - 1, Int(ceil(max(a.x, b.x) + rad)) - box.x)
            let y0 = max(0, Int(floor(min(a.y, b.y) - rad)) - box.y)
            let y1 = min(box.h - 1, Int(ceil(max(a.y, b.y) + rad)) - box.y)
            guard x0 <= x1, y0 <= y1 else { continue }
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            for yy in y0...y1 {
                for xx in x0...x1 {
                    let px = Double(box.x + xx) + 0.5, py = Double(box.y + yy) + 0.5
                    var t = len2 > 0 ? ((px - a.x) * dx + (py - a.y) * dy) / len2 : 0
                    t = min(1, max(0, t))
                    let cx = a.x + t * dx - px, cy = a.y + t * dy - py
                    if cx * cx + cy * cy <= r2 { bits[yy * box.w + xx] = 1 }
                }
            }
        }
        // A tiny brush can miss every pixel center; there is nothing to heal then.
        guard bits.contains(where: { $0 != 0 }) else { return nil }
        return HealMask(rect: box, bits: bits)
    }
}
