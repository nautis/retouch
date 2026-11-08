import RetouchCore
import SwiftUI

/// Camera Raw step for CR3 files: choose a look and lens correction, then open at full resolution.
struct DevelopPanelView: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Camera Raw")
                .font(.title2)
                .bold()
            if let info = model.rawInfo {
                LabeledContent("Size", value: "\(info.width) × \(info.height) px")
            }
            Picker("Look", selection: $model.rawSettings.look) {
                ForEach(RawLook.allCases) { look in
                    LookRow(look: look).tag(look)
                }
            }
            .pickerStyle(.radioGroup)
            .disabled(model.isFinishingDevelop)
            Toggle("Lens correction", isOn: $model.rawSettings.lensCorrection)
                .disabled(!(model.rawInfo?.lensCorrectionSupported ?? false) || model.isFinishingDevelop)
                .help("Fixes distortion using the lens profile Apple's RAW engine has for your lens")
            Text("The original CR3 is never changed. Your look and lens setting are remembered for the next file.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            HStack {
                Button("Cancel", role: .cancel, action: cancel)
                Spacer()
                Button("Open Image", action: open)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isFinishingDevelop)
            }
        }
        .padding()
        .frame(width: Design.developPanelWidth)
    }

    private func open() {
        Task { await model.finishDevelop() }
    }

    private func cancel() {
        model.window?.performClose(nil)
    }
}
