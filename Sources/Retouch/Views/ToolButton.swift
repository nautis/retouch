import SwiftUI

/// One tool in the palette. Icon-only on screen; the title is still read by VoiceOver.
struct ToolButton: View {
    let tool: Tool
    let isSelected: Bool
    let select: (Tool) -> Void

    var body: some View {
        Button(tool.title, systemImage: tool.symbol, action: choose)
            .labelStyle(.iconOnly)
            .font(.title3)
            .frame(width: Design.toolButtonSize, height: Design.toolButtonSize)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: Design.cornerRadius))
            .contentShape(.rect)
            .buttonStyle(.plain)
            .help(tool.helpText)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func choose() {
        select(tool)
    }
}
