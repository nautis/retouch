import Foundation

/// Where a window is in its life: opening a file, choosing a RAW look, editing, or failed to open.
enum EditorMode: Equatable {
    case loading
    case developing
    case editing
    case failed(String)
}
