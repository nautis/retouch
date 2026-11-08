import SwiftUI

/// Shared sizes, spacing and colors so every panel looks the same.
enum Design {
    static let toolButtonSize = 34.0
    static let toolStripWidth = 50.0
    static let developPanelWidth = 280.0
    static let dialogWidth = 380.0
    static let numberFieldWidth = 64.0
    static let cornerRadius = 7.0
    /// Gap between a floating filter panel and the canvas's top-right corner.
    static let floatingPanelInset = 16.0

    /// Neutral canvas surround, like Photoshop's pasteboard: doesn't tint how colors look.
    static let canvasBackground = NSColor(white: 0.19, alpha: 1)
    /// Heal stroke overlay while painting.
    static let strokeOverlay = NSColor.systemPink.withAlphaComponent(0.45)

    static let minBrushSize = 1.0
    static let maxBrushSize = 800.0

    /// Delay before a dialog's live preview re-renders after a slider moves.
    static let previewDebounce = Duration.milliseconds(120)
}
