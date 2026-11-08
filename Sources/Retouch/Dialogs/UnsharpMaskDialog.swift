import RetouchCore
import SwiftUI

/// Filter > Sharpen > Unsharp Mask, with Photoshop's three controls and a live preview.
struct UnsharpMaskDialog: View {
    @Bindable var model: EditorModel
    @AppStorage("usm.amount") private var amount = 100.0
    @AppStorage("usm.radius") private var radius = 1.0
    @AppStorage("usm.threshold") private var threshold = 0.0

    var body: some View {
        DialogChrome(title: "Unsharp Mask", applyTitle: "OK", showPreview: $model.showPreview,
                     onCancel: cancel, onApply: apply) {
            SliderField(title: "Amount", value: $amount, range: 1...500, unit: "%", decimals: 0)
            SliderField(title: "Radius", value: $radius, range: 0.1...100, unit: "px", decimals: 1)
            SliderField(title: "Threshold", value: $threshold, range: 0...255, unit: "levels", decimals: 0)
        }
        .task(id: op, updatePreview)
    }

    private var op: FilterOp {
        .unsharpMask(amount: amount, radius: radius, threshold: Int(threshold))
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
