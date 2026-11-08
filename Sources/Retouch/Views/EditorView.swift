import RetouchCore
import SwiftUI

/// One editor window: tools on the left, options bar on top, canvas, status bar,
/// and the Camera Raw panel on the right while a RAW file is being developed.
struct EditorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        HStack(spacing: 0) {
            ToolStripView(model: model)
            Divider()
            VStack(spacing: 0) {
                OptionsBarView(model: model)
                Divider()
                CanvasAreaView(model: model)
                Divider()
                StatusBarView(model: model)
            }
            if model.mode == .developing {
                Divider()
                DevelopPanelView(model: model)
            }
        }
        .sheet(item: sheetDialog, onDismiss: dialogClosed) { dialog in
            DialogHostView(model: model, dialog: dialog)
        }
        .alert("Couldn't complete that", item: $model.errorMessage) { _ in
        } message: { message in
            Text(message)
        }
        .dropDestination(for: URL.self, action: openDropped)
    }

    /// Dialogs without a live preview are sheets. The filter dialogs float in a panel over the
    /// canvas instead (see EditorWindowController), so they never reach this binding.
    private var sheetDialog: Binding<ActiveDialog?> {
        Binding(get: { model.dialog?.floatsOverCanvas == true ? nil : model.dialog },
                set: { model.dialog = $0 })
    }

    private func dialogClosed() {
        Task { await model.dialogDidClose() }
    }

    private func openDropped(_ urls: [URL], _ location: CGPoint) -> Bool {
        AppDelegate.shared?.open(urls)
        return !urls.isEmpty
    }
}
