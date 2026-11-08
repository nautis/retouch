import SwiftUI

/// Zoom, image size, selection size and what's running, along the bottom.
struct StatusBarView: View {
    let model: EditorModel

    var body: some View {
        HStack(spacing: 18) {
            Text("\(model.zoomPercent, format: .number.precision(.fractionLength(0...1)))%")
                .monospacedDigit()
            if model.imageSize.width > 0 {
                Text("\(Int(model.imageSize.width)) × \(Int(model.imageSize.height)) px")
                    .monospacedDigit()
            }
            if let s = model.selection {
                Label("\(s.w) × \(s.h)", systemImage: "rectangle.dashed")
                    .monospacedDigit()
            }
            Spacer()
            if let busy = model.busyMessage {
                ProgressView()
                    .controlSize(.small)
                Text(busy)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}
