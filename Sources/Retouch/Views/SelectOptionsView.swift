import SwiftUI

/// Rectangle Select options: aspect ratio, plus Crop and Deselect for the current selection.
struct SelectOptionsView: View {
    @Bindable var model: EditorModel

    var body: some View {
        Picker("Ratio", selection: $model.selectionRatio) {
            ForEach(SelectionRatio.allCases) { ratio in
                Text(ratio.title).tag(ratio)
            }
        }
        .fixedSize()
        Button("Crop to Selection", systemImage: "crop", action: crop)
            .disabled(model.selection == nil || !model.canEdit)
        Button("Deselect", action: model.deselect)
            .disabled(model.selection == nil)
        Text("Drag to select · drag inside to move it · Shift for a square · Return crops")
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func crop() {
        Task { await model.cropToSelection() }
    }
}
