import Foundation

/// Undo/redo. Small edits (healing, magic eraser, filters inside a selection) store only the changed
/// rectangle; whole-image edits (crop, resize, rotate) store the full before/after buffers.
public final class History {


    public private(set) var undoStack: [HistoryStep] = []
    public private(set) var redoStack: [HistoryStep] = []
    /// The newest step pruning dropped. Its result is the oldest state undo can still reach,
    /// which is not the original image.
    public private(set) var baseStepID: UUID?
    /// Oldest steps are dropped beyond this many bytes.
    public var byteLimit: Int

    /// Identifies the state the buffer is in: after the last applied step, or the pruned baseline.
    public var currentStateID: UUID? { undoStack.last?.id ?? baseStepID }

    public init(byteLimit: Int = 8 << 30) {
        self.byteLimit = byteLimit
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var undoName: String? { undoStack.last?.name }
    public var redoName: String? { redoStack.last?.name }

    public func record(_ name: String, _ change: HistoryChange) {
        undoStack.append(HistoryStep(name: name, change: change))
        redoStack.removeAll()
        var total = undoStack.reduce(0) { $0 + $1.change.bytes }
        while total > byteLimit && undoStack.count > 1 {
            let dropped = undoStack.removeFirst()
            total -= dropped.change.bytes
            baseStepID = dropped.id
        }
    }

    /// Applies a region edit to `buffer` and records it.
    public func applyRegion(_ name: String, rect: IRect, after: [UInt8], to buffer: inout PixelBuffer) {
        let before = buffer.copyRegion(rect)
        buffer.writeRegion(rect, after)
        record(name, .region(rect: rect, before: before, after: after))
    }

    /// Replaces `buffer` and records it.
    public func applyWhole(_ name: String, newBuffer: PixelBuffer, to buffer: inout PixelBuffer) {
        record(name, .whole(before: buffer, after: newBuffer))
        buffer = newBuffer
    }

    @discardableResult
    public func undo(_ buffer: inout PixelBuffer) -> String? {
        guard let step = undoStack.popLast() else { return nil }
        switch step.change {
        case let .region(rect, before, _): buffer.writeRegion(rect, before)
        case let .whole(before, _): buffer = before
        }
        redoStack.append(step)
        return step.name
    }

    @discardableResult
    public func redo(_ buffer: inout PixelBuffer) -> String? {
        guard let step = redoStack.popLast() else { return nil }
        switch step.change {
        case let .region(rect, _, after): buffer.writeRegion(rect, after)
        case let .whole(_, after): buffer = after
        }
        undoStack.append(step)
        return step.name
    }
}
