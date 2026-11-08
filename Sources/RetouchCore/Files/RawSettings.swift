import Foundation

public struct RawSettings: Equatable, Codable, Sendable {
    public var look: RawLook
    public var lensCorrection: Bool

    public init(look: RawLook = .standard, lensCorrection: Bool = true) {
        self.look = look
        self.lensCorrection = lensCorrection
    }
}
