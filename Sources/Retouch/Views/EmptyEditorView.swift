import SwiftUI

/// The window shown when no image is open: the editor's frame with an empty canvas, so the app
/// launches into a workspace (like Photoshop) and images are opened with ⌘O or by dropping them.
struct EmptyEditorView: View {
    let onOpen: () -> Void
    let onDrop: ([URL]) -> Void
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            toolStrip
            Divider()
            VStack(spacing: 0) {
                optionsBar
                Divider()
                canvas
                Divider()
                statusBar
            }
        }
        .dropDestination(for: URL.self, action: drop, isTargeted: setTargeted)
    }

    /// The real tools, greyed out, so the window reads as the editor it becomes.
    private var toolStrip: some View {
        VStack(spacing: 6) {
            ForEach(Tool.allCases) { tool in
                ToolButton(tool: tool, isSelected: false, select: ignore)
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .frame(width: Design.toolStripWidth)
        .disabled(true)
    }

    private var optionsBar: some View {
        HStack {
            Text("Open one or more images to start.")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var canvas: some View {
        ZStack {
            Color(nsColor: Design.canvasBackground)
            VStack(spacing: 14) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.white.opacity(0.45))
                    .accessibilityHidden(true)
                Text("Drop photos here, or open them with ⌘O")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))
                Text("Raw, JPG, PNG, HEIC and TIFF. Each image opens in its own tab.")
                    .foregroundStyle(.white.opacity(0.5))
                Button("Open…", action: onOpen)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 6)
            }
            .multilineTextAlignment(.center)
            .padding(40)
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.tint, lineWidth: 3)
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Same height as the editor's status bar, so the chrome doesn't jump when an image opens.
    private var statusBar: some View {
        HStack {
            Text(" ")
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private func ignore(_ tool: Tool) {}

    private func drop(_ urls: [URL], _ location: CGPoint) -> Bool {
        onDrop(urls)
        return !urls.isEmpty
    }

    private func setTargeted(_ targeted: Bool) {
        isTargeted = targeted
    }
}
