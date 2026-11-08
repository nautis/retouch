import Foundation

/// The pixels an undoable edit replaced, and the pixels it put in their place.
public enum HistoryChange: Sendable {
    case region(rect: IRect, before: [UInt8], after: [UInt8])
    case whole(before: PixelBuffer, after: PixelBuffer)

    var bytes: Int {
        switch self {
        case let .region(_, b, a): return b.count + a.count
        case let .whole(b, a): return b.byteCount + a.byteCount
        }
    }
}
