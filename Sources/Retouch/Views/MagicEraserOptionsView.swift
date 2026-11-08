import SwiftUI

/// Magic Eraser options, matching Photoshop's: tolerance, anti-alias, contiguous.
struct MagicEraserOptionsView: View {
    @Bindable var model: EditorModel

    var body: some View {
        SliderField(title: "Tolerance", value: $model.tolerance, range: 0...255, unit: "", decimals: 0)
            .frame(maxWidth: 320)
        Toggle("Anti-alias", isOn: $model.antiAlias)
        Toggle("Contiguous", isOn: $model.contiguous)
        Text("Click a color to make it transparent")
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
