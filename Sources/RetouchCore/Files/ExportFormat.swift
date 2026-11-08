import Foundation
import UniformTypeIdentifiers

public enum ExportFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case jpeg, png
    public var id: String { rawValue }
    public var fileExtension: String { self == .jpeg ? "jpg" : "png" }
    public var title: String { self == .jpeg ? "JPG" : "PNG" }
    public var utType: UTType { self == .jpeg ? .jpeg : .png }
}
