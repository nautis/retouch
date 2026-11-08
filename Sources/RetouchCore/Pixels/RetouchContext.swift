import CoreImage

public enum RetouchContext {
    /// One shared Core Image context. Intermediates are not cached: images are large and edits are one-off.
    public static let shared = CIContext(options: [.cacheIntermediates: false, .name: "Retouch"])
}
