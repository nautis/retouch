import RetouchCore
import SwiftUI

/// Hosts the AppKit canvas inside the SwiftUI editor layout.
struct CanvasRepresentable: NSViewRepresentable {
    let model: EditorModel

    func makeNSView(context: Context) -> CanvasView {
        let view = CanvasView(frame: .zero)
        view.model = model
        model.canvas = view
        return view
    }

    func updateNSView(_ view: CanvasView, context: Context) {
        // Reading these here subscribes SwiftUI to them, so the canvas refreshes when they change.
        view.update(image: model.displayImage, size: model.imageSize,
                    fitRequest: model.fitRequest, selection: model.selection)
        _ = model.tool
        _ = model.brushSize
        view.drawBrushCursor()
    }
}
