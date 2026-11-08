import Foundation

public enum RawLook: String, CaseIterable, Codable, Identifiable, Sendable {
    case standard, vivid, landscape, flat

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: return "Standard"
        case .vivid: return "Vivid"
        case .landscape: return "Landscape"
        case .flat: return "Flat"
        }
    }

    public var blurb: String {
        switch self {
        case .standard: return "Apple's default rendering"
        case .vivid: return "More color and contrast"
        case .landscape: return "Highlights down, shadows up, more color"
        case .flat: return "Low contrast, for retouching"
        }
    }
}
