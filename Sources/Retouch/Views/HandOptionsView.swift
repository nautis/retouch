import SwiftUI

/// Hand tool hint (it has no settings).
struct HandOptionsView: View {
    var body: some View {
        Text("Drag to move around · scroll to pan · pinch or ⌥-scroll to zoom · hold Space with any tool")
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
