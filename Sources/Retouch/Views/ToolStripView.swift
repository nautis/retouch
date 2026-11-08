import SwiftUI

/// The vertical tool palette on the left edge.
struct ToolStripView: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Tool.allCases) { tool in
                ToolButton(tool: tool, isSelected: model.tool == tool, select: choose)
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .frame(width: Design.toolStripWidth)
        .disabled(model.mode != .editing)
    }

    private func choose(_ tool: Tool) {
        model.tool = tool
        model.canvas?.window?.makeFirstResponder(model.canvas)
    }
}
