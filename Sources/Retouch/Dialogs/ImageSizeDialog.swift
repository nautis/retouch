import SwiftUI

/// Image > Image Size: new pixel dimensions, proportions locked by default, high-quality resampling.
struct ImageSizeDialog: View {
    let model: EditorModel
    @State private var width = 0
    @State private var height = 0
    @State private var constrain = true
    @State private var percent = 100.0

    var body: some View {
        DialogChrome(title: "Image Size", applyTitle: "OK", onCancel: cancel, onApply: apply) {
            LabeledContent("Current", value: "\(originalWidth) × \(originalHeight) px")
            TextField("Width (px)", value: $width, format: .number.grouping(.never))
            TextField("Height (px)", value: $height, format: .number.grouping(.never))
            Toggle("Constrain proportions", isOn: $constrain)
            SliderField(title: "Scale", value: $percent, range: 1...400, unit: "%", decimals: 0)
            Text("Resampled with Lanczos (sharp, high quality).")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: load)
        .onChange(of: width, widthChanged)
        .onChange(of: height, heightChanged)
        .onChange(of: percent, percentChanged)
    }

    private var originalWidth: Int { Int(model.imageSize.width) }
    private var originalHeight: Int { Int(model.imageSize.height) }

    private func load() {
        width = originalWidth
        height = originalHeight
    }

    private func widthChanged() {
        guard constrain, originalWidth > 0, width > 0 else { return }
        let h = max(1, Int((Double(width) * Double(originalHeight) / Double(originalWidth)).rounded()))
        if h != height { height = h }
        syncPercent()
    }

    private func heightChanged() {
        guard constrain, originalHeight > 0, height > 0 else { return }
        let w = max(1, Int((Double(height) * Double(originalWidth) / Double(originalHeight)).rounded()))
        if w != width { width = w }
        syncPercent()
    }

    private func syncPercent() {
        // Keep the exact value (the field shows it rounded) so percentChanged maps straight back to
        // this width instead of rewriting a typed 1600 as the 1638 that a rounded 20% would give.
        let p = Double(width) / Double(max(1, originalWidth)) * 100
        if abs(p - percent) > 0.05 { percent = p }
    }

    private func percentChanged() {
        let w = max(1, Int((Double(originalWidth) * percent / 100).rounded()))
        guard w != width else { return }
        width = w
        height = max(1, Int((Double(originalHeight) * percent / 100).rounded()))
    }

    private func cancel() {
        model.dialog = nil
    }

    private func apply() {
        let w = width, h = height
        model.dialog = nil
        Task { await model.resize(width: w, height: h) }
    }
}
