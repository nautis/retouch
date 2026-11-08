import RetouchCore
import SwiftUI

/// File > Export As: format, quality, size, color conversion. Metadata is never copied.
struct ExportDialog: View {
    let model: EditorModel
    @State private var format = ExportFormat.jpeg
    @State private var quality = 90.0
    @State private var width = 0
    @State private var height = 0
    @State private var convertToSRGB = true

    var body: some View {
        DialogChrome(title: "Export As", applyTitle: "Export…", onCancel: cancel, onApply: export) {
            Picker("Format", selection: $format) {
                ForEach(ExportFormat.allCases) { f in
                    Text(f.title).tag(f)
                }
            }
            .pickerStyle(.segmented)
            if format == .jpeg {
                SliderField(title: "Quality", value: $quality, range: 1...100, unit: "%", decimals: 0)
            } else {
                Text("PNG keeps transparency (for magic-erased images).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            TextField("Width (px)", value: $width, format: .number.grouping(.never))
            TextField("Height (px)", value: $height, format: .number.grouping(.never))
            Button("Full Size", action: resetSize)
                .disabled(width == fullWidth && height == fullHeight)
            Toggle("Convert to sRGB", isOn: $convertToSRGB)
                .help("Best for the web and email. Off keeps the wider Display P3 colors.")
        }
        .onAppear(perform: load)
        .onChange(of: width, widthChanged)
    }

    private var fullWidth: Int { Int(model.imageSize.width) }
    private var fullHeight: Int { Int(model.imageSize.height) }

    private func load() {
        let o = model.defaultExportOptions()
        format = o.format
        quality = (o.quality * 100).rounded()
        width = o.width
        height = o.height
        convertToSRGB = o.convertToSRGB
    }

    private func widthChanged() {
        guard fullWidth > 0, width > 0 else { return }
        let h = max(1, Int((Double(width) * Double(fullHeight) / Double(fullWidth)).rounded()))
        if h != height { height = h }
    }

    private func resetSize() {
        width = fullWidth
        height = fullHeight
    }

    private func cancel() {
        model.closeAfterExport = false
        model.dialog = nil
    }

    private func export() {
        let options = ExportOptions(format: format, quality: quality / 100, width: max(1, width),
                                    height: max(1, height), convertToSRGB: convertToSRGB)
        model.dialog = nil
        model.chooseDestinationAndExport(options)
    }
}
