import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageFiles {
    public static let openableTypes: [UTType] = [
        .jpeg, .png, .heic, .tiff, .rawImage,
        UTType("com.canon.cr3-raw-image") ?? .rawImage,
    ]

    public static func isRaw(_ url: URL) -> Bool {
        guard let t = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return t.conforms(to: .rawImage)
    }

    public static func rawInfo(_ url: URL) throws -> RawInfo {
        guard let raw = CIRAWFilter(imageURL: url) else { throw ImageFileError.notRaw(url) }
        // The output extent, not nativeSize: nativeSize ignores the camera orientation, so a portrait
        // shot would report landscape dimensions and the develop preview would be stretched to them.
        let size = raw.outputImage?.extent.integral.size ?? raw.nativeSize
        return RawInfo(
            width: Int(size.width), height: Int(size.height),
            lensCorrectionSupported: raw.isLensCorrectionSupported)
    }

    /// Develops a RAW file. `maxDimension` renders a smaller preview (fast); nil renders full resolution.
    public static func developRaw(_ url: URL, settings: RawSettings, maxDimension: Int? = nil,
                                  context: CIContext = RetouchContext.shared) throws -> PixelBuffer {
        guard let raw = CIRAWFilter(imageURL: url) else { throw ImageFileError.notRaw(url) }
        if raw.isLensCorrectionSupported {
            raw.isLensCorrectionEnabled = settings.lensCorrection
        }
        let native = raw.nativeSize
        if let maxDim = maxDimension {
            let s = min(1.0, Double(maxDim) / Double(max(native.width, native.height)))
            raw.scaleFactor = Float(s)
        }
        if settings.look == .flat {
            raw.boostAmount = 0
        }
        guard var img = raw.outputImage else { throw ImageFileError.unreadable(url) }
        switch settings.look {
        case .standard:
            break
        case .flat:
            img = img.applyingFilter("CIColorControls", parameters: [
                "inputSaturation": 0.95, "inputContrast": 0.88, "inputBrightness": 0.0,
            ])
        case .vivid:
            img = img.applyingFilter("CIVibrance", parameters: ["inputAmount": 0.45])
                .applyingFilter("CIColorControls", parameters: [
                    "inputSaturation": 1.06, "inputContrast": 1.05, "inputBrightness": 0.0,
                ])
        case .landscape:
            img = img.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": 0.8, "inputShadowAmount": 0.35, "inputRadius": 0.0,
            ])
            .applyingFilter("CIVibrance", parameters: ["inputAmount": 0.35])
        }
        let e = img.extent.integral
        img = img.cropped(to: e).transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
        return PixelBuffer.render(img, width: Int(e.width), height: Int(e.height), context: context)
    }

    /// Opens JPEG, PNG, HEIC, TIFF. EXIF orientation is applied to the pixels.
    public static func loadRaster(_ url: URL, context: CIContext = RetouchContext.shared) throws -> PixelBuffer {
        guard let ci = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw ImageFileError.unreadable(url)
        }
        let e = ci.extent.integral
        let img = ci.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
        return PixelBuffer.render(img, width: Int(e.width), height: Int(e.height), context: context)
    }

    // MARK: - Export


    /// Writes the buffer. JPG has no transparency, so transparent pixels are flattened onto white.
    /// No metadata is copied from the original.
    public static func export(_ buffer: PixelBuffer, to url: URL, options: ExportOptions,
                              context: CIContext = RetouchContext.shared) throws {
        var src = buffer
        if options.width != buffer.width || options.height != buffer.height {
            src = Transforms.resize(buffer, width: options.width, height: options.height, context: context)
        }
        var img = src.ciImage()
        let space = options.convertToSRGB ? PixelBuffer.sRGB : PixelBuffer.colorSpace
        let data: Data?
        switch options.format {
        case .jpeg:
            if src.hasTransparency {
                let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: img.extent)
                img = img.composited(over: white)
            }
            data = context.jpegRepresentation(
                of: img, colorSpace: space,
                options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): options.quality])
        case .png:
            data = context.pngRepresentation(of: img, format: .RGBA8, colorSpace: space, options: [:])
        }
        guard let bytes = data else { throw ImageFileError.writeFailed(url, "encoder returned no data") }
        do {
            try bytes.write(to: url, options: .atomic)
        } catch {
            throw ImageFileError.writeFailed(url, error.localizedDescription)
        }
    }
}
