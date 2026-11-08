import SwiftUI

/// Spot Healing Brush options: brush size.
struct HealOptionsView: View {
    @Bindable var model: EditorModel

    var body: some View {
        SliderField(title: "Size", value: $model.brushSize,
                    range: Design.minBrushSize...Design.maxBrushSize, unit: "px", decimals: 0)
            .frame(maxWidth: 360)
        Text("Paint over a spot or scratch · [ and ] change size")
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
