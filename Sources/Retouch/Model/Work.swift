import CoreGraphics
import Foundation
import RetouchCore

/// The heavy image work, run off the main thread so the window stays responsive.
/// Every input and output is a value type, so nothing is shared between threads.
enum Work {
    /// Display images larger than this are downscaled for the screen (GPU texture limit).
    static let maxTextureSide = 16_384

    @concurrent
    static func displayImage(_ buffer: PixelBuffer) async -> CGImage {
        if max(buffer.width, buffer.height) <= maxTextureSide { return buffer.makeCGImage() }
        let s = Double(maxTextureSide) / Double(max(buffer.width, buffer.height))
        let small = Transforms.resize(buffer, width: max(1, Int(Double(buffer.width) * s)),
                                      height: max(1, Int(Double(buffer.height) * s)))
        return small.makeCGImage()
    }

    @concurrent
    static func rawInfo(_ url: URL) async throws -> RawInfo {
        try ImageFiles.rawInfo(url)
    }

    @concurrent
    static func develop(_ url: URL, settings: RawSettings, maxDimension: Int?) async throws -> PixelBuffer {
        try ImageFiles.developRaw(url, settings: settings, maxDimension: maxDimension)
    }

    @concurrent
    static func loadRaster(_ url: URL) async throws -> PixelBuffer {
        try ImageFiles.loadRaster(url)
    }

    @concurrent
    static func heal(_ buffer: PixelBuffer, mask: HealMask) async -> [UInt8] {
        Inpainter.heal(buffer, mask: mask)
    }

    @concurrent
    static func magicErase(_ buffer: PixelBuffer, x: Int, y: Int, tolerance: Int,
                           contiguous: Bool, antiAlias: Bool) async -> MagicEraseResult? {
        MagicEraser.erase(buffer, x: x, y: y, tolerance: tolerance, contiguous: contiguous, antiAlias: antiAlias)
    }

    @concurrent
    static func filter(_ op: FilterOp, _ buffer: PixelBuffer, rect: IRect) async -> [UInt8] {
        Filters.apply(op, to: buffer, rect: rect)
    }

    @concurrent
    static func auto(_ kind: AutoAdjust, _ buffer: PixelBuffer, rect: IRect) async -> [UInt8] {
        kind.apply(to: buffer, rect: rect)
    }

    @concurrent
    static func resize(_ buffer: PixelBuffer, width: Int, height: Int) async -> PixelBuffer {
        Transforms.resize(buffer, width: width, height: height)
    }

    @concurrent
    static func rotate(_ buffer: PixelBuffer, degrees: Double) async -> PixelBuffer {
        switch degrees {
        case 90: buffer.rotated90(clockwise: true)
        case -90: buffer.rotated90(clockwise: false)
        case 180, -180: buffer.rotated180()
        default: Transforms.rotate(buffer, degrees: degrees)
        }
    }

    @concurrent
    static func crop(_ buffer: PixelBuffer, to rect: IRect) async -> PixelBuffer {
        buffer.cropped(rect)
    }

    @concurrent
    static func export(_ buffer: PixelBuffer, to url: URL, options: ExportOptions) async throws {
        try ImageFiles.export(buffer, to: url, options: options)
    }
}
