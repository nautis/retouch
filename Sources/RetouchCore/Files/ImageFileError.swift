import Foundation

public enum ImageFileError: LocalizedError {
    case unreadable(URL)
    case notRaw(URL)
    case writeFailed(URL, String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let u): return "Couldn't read \(u.lastPathComponent)."
        case .notRaw(let u): return "\(u.lastPathComponent) isn't a camera RAW file macOS can decode."
        case .writeFailed(let u, let why): return "Couldn't save \(u.lastPathComponent): \(why)"
        }
    }
}
