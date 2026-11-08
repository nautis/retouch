import Foundation

/// Integer pixel rectangle, top-left origin (row 0 is the top of the image).
public struct IRect: Equatable, Hashable, Sendable, CustomStringConvertible {
    public var x: Int
    public var y: Int
    public var w: Int
    public var h: Int

    public init(x: Int, y: Int, w: Int, h: Int) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    public var isEmpty: Bool { w <= 0 || h <= 0 }
    public var maxX: Int { x + w }
    public var maxY: Int { y + h }
    public var area: Int { max(0, w) * max(0, h) }
    public var description: String { "(\(x),\(y) \(w)x\(h))" }

    public func intersection(_ o: IRect) -> IRect {
        let nx = max(x, o.x)
        let ny = max(y, o.y)
        let mx = min(maxX, o.maxX)
        let my = min(maxY, o.maxY)
        return IRect(x: nx, y: ny, w: max(0, mx - nx), h: max(0, my - ny))
    }

    public func expanded(by m: Int) -> IRect {
        IRect(x: x - m, y: y - m, w: w + 2 * m, h: h + 2 * m)
    }

    public func contains(x px: Int, y py: Int) -> Bool {
        px >= x && py >= y && px < maxX && py < maxY
    }
}
