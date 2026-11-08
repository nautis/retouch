import RetouchCore
import SwiftUI

/// Filter > Pixelate > Mosaic / Crystallize / Pointillize.
struct PixelateDialog: View {
    @Bindable var model: EditorModel
    let kind: PixelateKind
    @State private var cellSize: Double

    init(model: EditorModel, kind: PixelateKind) {
        self.model = model
        self.kind = kind
        let saved = UserDefaults.standard.object(forKey: kind.defaultsKey) as? Double
        _cellSize = State(initialValue: saved ?? kind.defaultCellSize)
    }

    var body: some View {
        DialogChrome(title: kind.title, applyTitle: "OK", showPreview: $model.showPreview,
                     onCancel: cancel, onApply: apply) {
            SliderField(title: "Cell Size", value: $cellSize, range: kind.range, unit: "px", decimals: 0)
            if kind == .pointillize {
                Text("Gaps between dots are white, like Photoshop's default background color.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: op, updatePreview)
    }

    private var op: FilterOp { kind.op(cellSize: Int(cellSize.rounded())) }

    private func updatePreview() async {
        await model.preview(op)
    }

    private func cancel() {
        Task { await model.cancelPreview() }
    }

    private func apply() {
        UserDefaults.standard.set(cellSize, forKey: kind.defaultsKey)
        Task { await model.commitFilter(op) }
    }
}
