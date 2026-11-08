import Foundation

/// One entry in the undo or redo stack.
public struct HistoryStep: Sendable, Identifiable {
    public let id = UUID()
    public let name: String
    let change: HistoryChange
}
