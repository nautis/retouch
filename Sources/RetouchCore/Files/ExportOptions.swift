import Foundation

public struct ExportOptions: Equatable, Codable, Sendable {
    public var format: ExportFormat
    /// 0...1, JPG only.
    public var quality: Double
    public var width: Int
    public var height: Int
    public var convertToSRGB: Bool

    public init(format: ExportFormat = .jpeg, quality: Double = 0.9, width: Int, height: Int,
                convertToSRGB: Bool = true) {
        self.format = format
        self.quality = quality
        self.width = width
        self.height = height
        self.convertToSRGB = convertToSRGB
    }
}
