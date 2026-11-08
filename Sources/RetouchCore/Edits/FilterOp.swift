import Foundation

/// The filters Retouch offers. Each one applies to the selection, or to the whole image when there is none.
public enum FilterOp: Equatable, Hashable, Sendable {
    /// amount in percent (1...500), radius in pixels, threshold in levels (0...255)
    case unsharpMask(amount: Double, radius: Double, threshold: Int)
    case sharpen
    case mosaic(cellSize: Int)
    case crystallize(cellSize: Int)
    case pointillize(cellSize: Int)
    /// hue in degrees (-180...180), saturation and lightness in percent (-100...100)
    case hueSaturation(hue: Double, saturation: Double, lightness: Double)

    public var historyName: String {
        switch self {
        case .unsharpMask: return "Unsharp Mask"
        case .sharpen: return "Sharpen"
        case .mosaic: return "Mosaic"
        case .crystallize: return "Crystallize"
        case .pointillize: return "Pointillize"
        case .hueSaturation: return "Hue/Saturation"
        }
    }
}
