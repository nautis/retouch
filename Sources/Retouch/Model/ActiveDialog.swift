import Foundation

/// The dialog currently open over the editor.
enum ActiveDialog: String, Identifiable {
    case unsharpMask, mosaic, crystallize, pointillize, hueSaturation, imageSize, rotate, export

    var id: String { rawValue }

    /// Filters with a live preview float in a panel over the canvas instead of a sheet,
    /// because macOS dims the window behind a sheet and the preview can't be judged.
    var floatsOverCanvas: Bool {
        switch self {
        case .unsharpMask, .mosaic, .crystallize, .pointillize, .hueSaturation: true
        case .imageSize, .rotate, .export: false
        }
    }
}
