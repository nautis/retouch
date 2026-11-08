import SwiftUI

/// Settings for the current tool, across the top of the canvas (like Photoshop's options bar).
struct OptionsBarView: View {
    @Bindable var model: EditorModel

    var body: some View {
        HStack(spacing: 16) {
            if model.mode == .developing {
                Label("Camera Raw: pick a look on the right, then Open Image.", systemImage: "camera.aperture")
                    .foregroundStyle(.secondary)
            } else {
                switch model.tool {
                case .select: SelectOptionsView(model: model)
                case .heal: HealOptionsView(model: model)
                case .magicEraser: MagicEraserOptionsView(model: model)
                case .hand: HandOptionsView()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .disabled(model.mode == .editing && !model.canEdit && model.dialog == nil && model.busyMessage != nil)
    }
}
