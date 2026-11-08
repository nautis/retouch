import SwiftUI

/// Shared layout for every dialog: title, controls, optional Preview checkbox, Cancel and OK.
struct DialogChrome<Content: View>: View {
    let title: String
    let applyTitle: String
    var showPreview: Binding<Bool>?
    let onCancel: () -> Void
    let onApply: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
            Form {
                content
            }
            HStack {
                if let showPreview {
                    Toggle("Preview", isOn: showPreview)
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(applyTitle, action: onApply)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: Design.dialogWidth)
    }
}
