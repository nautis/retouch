import Foundation

/// What the magic eraser changed: the bounding rect of the erased area and its new pixels.
public struct MagicEraseResult: Sendable {
    public let rect: IRect
    public let pixels: [UInt8]
    public let erasedCount: Int
}
