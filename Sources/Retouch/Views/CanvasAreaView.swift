import SwiftUI

/// The canvas plus the overlays that replace it while a file opens or when it can't be read.
struct CanvasAreaView: View {
    let model: EditorModel

    var body: some View {
        ZStack {
            CanvasRepresentable(model: model)
            if case .failed(let message) = model.mode {
                ContentUnavailableView("Couldn't Open \(model.fileURL.lastPathComponent)",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(message))
                    .background(.background)
            }
            if model.mode == .loading {
                ProgressView(model.busyMessage ?? "Opening…")
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
