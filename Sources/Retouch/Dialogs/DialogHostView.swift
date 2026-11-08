import SwiftUI

/// Picks the sheet content for the active dialog.
struct DialogHostView: View {
    let model: EditorModel
    let dialog: ActiveDialog

    var body: some View {
        switch dialog {
        case .unsharpMask: UnsharpMaskDialog(model: model)
        case .mosaic: PixelateDialog(model: model, kind: .mosaic)
        case .crystallize: PixelateDialog(model: model, kind: .crystallize)
        case .pointillize: PixelateDialog(model: model, kind: .pointillize)
        case .hueSaturation: HueSaturationDialog(model: model)
        case .imageSize: ImageSizeDialog(model: model)
        case .rotate: RotateDialog(model: model)
        case .export: ExportDialog(model: model)
        }
    }
}
