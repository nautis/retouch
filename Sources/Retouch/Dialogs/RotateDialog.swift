import SwiftUI

/// Image > Image Rotation > Arbitrary: any angle, clockwise or counter-clockwise.
/// The canvas grows to fit and the new corners are transparent.
struct RotateDialog: View {
    let model: EditorModel
    @AppStorage("rotate.angle") private var angle = 1.0
    @AppStorage("rotate.clockwise") private var clockwise = true

    var body: some View {
        DialogChrome(title: "Rotate Canvas", applyTitle: "OK", onCancel: cancel, onApply: apply) {
            TextField("Angle (°)", value: $angle, format: .number.precision(.fractionLength(0...2)))
            Picker("Direction", selection: $clockwise) {
                Text("Clockwise").tag(true)
                Text("Counter-clockwise").tag(false)
            }
            .pickerStyle(.segmented)
            Text("Corners added by rotating are transparent. JPG export fills them with white.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func cancel() {
        model.dialog = nil
    }

    private func apply() {
        let degrees = min(max(angle, -359.99), 359.99) * (clockwise ? 1 : -1)
        model.dialog = nil
        guard degrees != 0 else { return }
        Task { await model.rotate(degrees: degrees) }
    }
}
