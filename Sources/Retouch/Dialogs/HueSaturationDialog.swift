import RetouchCore
import SwiftUI

/// Image > Adjustments > Hue/Saturation. Starts at zero each time, like Photoshop.
struct HueSaturationDialog: View {
    @Bindable var model: EditorModel
    @State private var hue = 0.0
    @State private var saturation = 0.0
    @State private var lightness = 0.0

    var body: some View {
        DialogChrome(title: "Hue/Saturation", applyTitle: "OK", showPreview: $model.showPreview,
                     onCancel: cancel, onApply: apply) {
            SliderField(title: "Hue", value: $hue, range: -180...180, unit: "°", decimals: 0)
            SliderField(title: "Saturation", value: $saturation, range: -100...100, unit: "", decimals: 0)
            SliderField(title: "Lightness", value: $lightness, range: -100...100, unit: "", decimals: 0)
        }
        .task(id: op, updatePreview)
    }

    private var op: FilterOp {
        .hueSaturation(hue: hue.rounded(), saturation: saturation.rounded(), lightness: lightness.rounded())
    }

    private func updatePreview() async {
        await model.preview(op)
    }

    private func cancel() {
        Task { await model.cancelPreview() }
    }

    private func apply() {
        Task { await model.commitFilter(op) }
    }
}
