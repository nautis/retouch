import CoreGraphics
import CoreImage
import Foundation

/// The document's pixels: 8-bit RGBA, premultiplied alpha, Display P3, top-left origin.
/// A struct over an Array, so copies are cheap until one side is mutated.
public struct PixelBuffer: Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]

    public static let colorSpace: CGColorSpace = {
        guard let space = CGColorSpace(name: CGColorSpace.displayP3) else {
            fatalError("Display P3 color space is missing from this system")
        }
        return space
    }()

    public static let sRGB: CGColorSpace = {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            fatalError("sRGB color space is missing from this system")
        }
        return space
    }()

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 4, "pixel count mismatch")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, fill: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)) {
        self.width = width
        self.height = height
        var p = [UInt8](repeating: 0, count: width * height * 4)
        if fill != (0, 0, 0, 0) {
            for i in stride(from: 0, to: p.count, by: 4) {
                p[i] = fill.0
                p[i + 1] = fill.1
                p[i + 2] = fill.2
                p[i + 3] = fill.3
            }
        }
        self.pixels = p
    }

    public var bounds: IRect { IRect(x: 0, y: 0, w: width, h: height) }
    public var byteCount: Int { pixels.count }

    // MARK: Core Graphics / Core Image bridges

    public func makeCGImage() -> CGImage {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: width * 4, space: PixelBuffer.colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else {
            fatalError("Couldn't wrap a \(width)x\(height) RGBA buffer in a CGImage")
        }
        return image
    }

    /// Core Image view of the buffer. Extent is (0, 0, width, height) with CI's bottom-left origin.
    public func ciImage() -> CIImage {
        CIImage(cgImage: makeCGImage())
    }

    /// Converts a top-left pixel rect to Core Image's bottom-left coordinates.
    public func ciRect(_ r: IRect) -> CGRect {
        CGRect(x: r.x, y: height - r.y - r.h, width: r.w, height: r.h)
    }

    /// Renders `image` (whose extent should start at the origin) into a new buffer of the given size.
    public static func render(_ image: CIImage, width: Int, height: Int, context: CIContext) -> PixelBuffer {
        var out = PixelBuffer(width: width, height: height)
        out.pixels.withUnsafeMutableBytes { raw in
            context.render(
                image, toBitmap: raw.baseAddress!, rowBytes: width * 4,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                format: .RGBA8, colorSpace: PixelBuffer.colorSpace)
        }
        return out
    }

    /// Renders `image` into the top-left rect `r` of this buffer's coordinate space and returns those bytes.
    public func renderRegion(_ image: CIImage, rect r: IRect, context: CIContext) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: r.area * 4)
        bytes.withUnsafeMutableBytes { raw in
            context.render(
                image, toBitmap: raw.baseAddress!, rowBytes: r.w * 4,
                bounds: ciRect(r), format: .RGBA8, colorSpace: PixelBuffer.colorSpace)
        }
        return bytes
    }

    // MARK: Regions

    public func copyRegion(_ r: IRect) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: r.area * 4)
        pixels.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for row in 0..<r.h {
                    let s = ((r.y + row) * width + r.x) * 4
                    let d = row * r.w * 4
                    for i in 0..<(r.w * 4) { dst[d + i] = src[s + i] }
                }
            }
        }
        return out
    }

    public mutating func writeRegion(_ r: IRect, _ bytes: [UInt8]) {
        precondition(bytes.count == r.area * 4, "region byte count mismatch")
        let w = width
        pixels.withUnsafeMutableBufferPointer { dst in
            bytes.withUnsafeBufferPointer { src in
                for row in 0..<r.h {
                    let d = ((r.y + row) * w + r.x) * 4
                    let s = row * r.w * 4
                    for i in 0..<(r.w * 4) { dst[d + i] = src[s + i] }
                }
            }
        }
    }

    public func cropped(_ r: IRect) -> PixelBuffer {
        let c = r.intersection(bounds)
        return PixelBuffer(width: c.w, height: c.h, pixels: copyRegion(c))
    }

    public func rotated90(clockwise: Bool) -> PixelBuffer {
        let nw = height
        let nh = width
        var out = [UInt8](repeating: 0, count: pixels.count)
        pixels.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for y in 0..<height {
                    for x in 0..<width {
                        // clockwise: (x, y) -> (h-1-y, x); counter-clockwise: (x, y) -> (y, w-1-x)
                        let nx = clockwise ? (height - 1 - y) : y
                        let ny = clockwise ? x : (width - 1 - x)
                        let s = (y * width + x) * 4
                        let d = (ny * nw + nx) * 4
                        dst[d] = src[s]
                        dst[d + 1] = src[s + 1]
                        dst[d + 2] = src[s + 2]
                        dst[d + 3] = src[s + 3]
                    }
                }
            }
        }
        return PixelBuffer(width: nw, height: nh, pixels: out)
    }

    public func rotated180() -> PixelBuffer {
        var out = [UInt8](repeating: 0, count: pixels.count)
        let n = width * height
        pixels.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for i in 0..<n {
                    let s = i * 4
                    let d = (n - 1 - i) * 4
                    dst[d] = src[s]
                    dst[d + 1] = src[s + 1]
                    dst[d + 2] = src[s + 2]
                    dst[d + 3] = src[s + 3]
                }
            }
        }
        return PixelBuffer(width: width, height: height, pixels: out)
    }

    public var hasTransparency: Bool {
        pixels.withUnsafeBufferPointer { p in
            var i = 3
            while i < p.count {
                if p[i] != 255 { return true }
                i += 4
            }
            return false
        }
    }
}
