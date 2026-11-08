import Foundation

/// The canvas tools. Shortcut letters follow Photoshop.
enum Tool: String, CaseIterable, Identifiable {
    case select, heal, magicEraser, hand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: "Rectangle Select"
        case .heal: "Spot Healing Brush"
        case .magicEraser: "Magic Eraser"
        case .hand: "Hand"
        }
    }

    var symbol: String {
        switch self {
        case .select: "rectangle.dashed"
        case .heal: "bandage"
        case .magicEraser: "eraser"
        case .hand: "hand.raised"
        }
    }

    var shortcut: Character {
        switch self {
        case .select: "m"
        case .heal: "j"
        case .magicEraser: "e"
        case .hand: "h"
        }
    }

    var helpText: String { "\(title) (\(String(shortcut).uppercased()))" }
}
