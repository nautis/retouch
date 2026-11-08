import CoreImage
import Foundation

/// Whole-image geometry: resize, arbitrary rotation.
public enum Transforms {
    /// High-quality (Lanczos) resample to exact pixel dimensions.
    public static func resize(_ buffer: PixelBuffer, width: Int, height: Int,
                              context: CIContext = RetouchContext.shared) -> PixelBuffer {
        precondition(width > 0 && height > 0)
        let sy = Double(height) / Double(buffer.height)
        let sx = Double(width) / Double(buffer.width)
        // Clamp first so edge pixels are not blended with transparency, then crop to the exact target.
        let scaled = buffer.ciImage().clampedToExtent()
            .applyingFilter("CILanczosScaleTransform", parameters: [
                "inputScale": sy, "inputAspectRatio": sx / sy,
            ])
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        var out = PixelBuffer.render(scaled, width: width, height: height, context: context)
        if !buffer.hasTransparency { out.forceOpaque() }
        return out
    }

    /// Rotates by `degrees` (positive = clockwise). The canvas grows to fit; new corners are transparent.
    public static func rotate(_ buffer: PixelBuffer, degrees: Double,
                              context: CIContext = RetouchContext.shared) -> PixelBuffer {
        let img = buffer.ciImage()
        // Core Image's y axis points up, so a visual clockwise turn is a negative angle.
        let rotated = img.transformed(by: CGAffineTransform(rotationAngle: -degrees * .pi / 180))
        let e = rotated.extent.integral
        let moved = rotated.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
        return PixelBuffer.render(moved, width: Int(e.width), height: Int(e.height), context: context)
    }
}

extension PixelBuffer {
    /// Sets alpha to 255 everywhere (used after resampling an opaque image, where edge math can leave 254s).
    mutating func forceOpaque() {
        pixels.withUnsafeMutableBufferPointer { p in
            var i = 3
            while i < p.count {
                p[i] = 255
                i += 4
            }
        }
    }
}
