import CoreImage
import Foundation

public enum Filters {
    /// Applies `op` inside `rect` (top-left pixel coordinates) and returns the new bytes for that rect.
    public static func apply(_ op: FilterOp, to buffer: PixelBuffer, rect: IRect,
                             context: CIContext = RetouchContext.shared) -> [UInt8] {
        let full = buffer.ciImage()
        let ciR = buffer.ciRect(rect)
        let output: CIImage
        switch op {
        case let .unsharpMask(amount, radius, threshold):
            let src = full.clampedToExtent()
            let sharp = src.applyingFilter("CIUnsharpMask", parameters: [
                "inputRadius": radius, "inputIntensity": amount / 100,
            ])
            if threshold > 0 {
                // Photoshop's threshold: only sharpen where the pixel differs from its blurred
                // neighbourhood by more than `threshold` levels.
                let blurred = src.applyingGaussianBlur(sigma: radius)
                let diff = src.applyingFilter("CIDifferenceBlendMode", parameters: [
                    kCIInputBackgroundImageKey: blurred,
                ])
                let mask = diff.applyingFilter("CIColorThreshold", parameters: [
                    "inputThreshold": Double(threshold) / 255,
                ])
                output = sharp.applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: src, kCIInputMaskImageKey: mask,
                ])
            } else {
                output = sharp
            }
        case .sharpen:
            output = full.clampedToExtent().applyingFilter("CISharpenLuminance", parameters: [
                "inputSharpness": 0.5, "inputRadius": 1.0,
            ])
        case let .mosaic(cell):
            // Grid starts at the top-left corner of the selection, like Photoshop.
            let src = full.cropped(to: ciR).clampedToExtent()
            output = src.applyingFilter("CIPixellate", parameters: [
                "inputScale": max(2, cell),
                kCIInputCenterKey: CIVector(x: ciR.minX, y: ciR.maxY),
            ])
        case let .crystallize(cell):
            let src = full.cropped(to: ciR).clampedToExtent()
            output = src.applyingFilter("CICrystallize", parameters: [
                "inputRadius": max(1.5, Double(cell) / 2),
                kCIInputCenterKey: CIVector(x: ciR.minX, y: ciR.maxY),
            ])
        case let .pointillize(cell):
            let src = full.cropped(to: ciR).clampedToExtent()
            output = src.applyingFilter("CIPointillize", parameters: [
                "inputRadius": max(1.5, Double(cell) / 2),
                kCIInputCenterKey: CIVector(x: ciR.minX, y: ciR.maxY),
            ])
        case let .hueSaturation(hue, sat, light):
            var img = full
            if hue != 0 {
                img = img.applyingFilter("CIHueAdjust", parameters: ["inputAngle": hue * .pi / 180])
            }
            if sat != 0 {
                img = img.applyingFilter("CIColorControls", parameters: [
                    "inputSaturation": 1 + sat / 100, "inputBrightness": 0.0, "inputContrast": 1.0,
                ])
            }
            if light != 0 {
                // Photoshop lightness blends toward white (positive) or black (negative).
                let k = abs(light) / 100
                let scale = 1 - k
                let bias = light > 0 ? k : 0
                img = img.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0),
                ])
            }
            output = img
        }
        var bytes = buffer.renderRegion(output, rect: rect, context: context)
        restoreAlpha(&bytes, from: buffer, rect: rect)
        return bytes
    }

    /// Filters change color, not transparency. Clamped sampling can nudge alpha at the edges,
    /// so copy the original alpha back and re-clamp the premultiplied color under it.
    static func restoreAlpha(_ bytes: inout [UInt8], from buffer: PixelBuffer, rect: IRect) {
        let original = buffer.copyRegion(rect)
        bytes.withUnsafeMutableBufferPointer { b in
            original.withUnsafeBufferPointer { o in
                var i = 0
                while i < b.count {
                    let a = o[i + 3]
                    b[i + 3] = a
                    if a < 255 {
                        b[i] = min(b[i], a)
                        b[i + 1] = min(b[i + 1], a)
                        b[i + 2] = min(b[i + 2], a)
                    }
                    i += 4
                }
            }
        }
    }
}
