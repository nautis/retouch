import RetouchCore

/// The three Pixelate filters share one dialog: a cell size.
enum PixelateKind: String {
    case mosaic, crystallize, pointillize

    var title: String {
        switch self {
        case .mosaic: "Mosaic"
        case .crystallize: "Crystallize"
        case .pointillize: "Pointillize"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .mosaic: 2...200
        case .crystallize, .pointillize: 3...300
        }
    }

    var defaultCellSize: Double {
        switch self {
        case .mosaic: 10
        case .crystallize: 10
        case .pointillize: 5
        }
    }

    /// Where the last-used cell size is remembered.
    var defaultsKey: String { "pixelate.\(rawValue)" }

    func op(cellSize: Int) -> FilterOp {
        switch self {
        case .mosaic: .mosaic(cellSize: cellSize)
        case .crystallize: .crystallize(cellSize: cellSize)
        case .pointillize: .pointillize(cellSize: cellSize)
        }
    }
}
