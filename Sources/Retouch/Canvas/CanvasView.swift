import AppKit
import QuartzCore
import RetouchCore

/// The image canvas: draws the photo with Core Animation (GPU-scaled, so 45 MP pans smoothly),
/// and turns mouse input into selections, heal strokes, magic-eraser clicks, panning and zooming.
@MainActor
final class CanvasView: NSView {
    weak var model: EditorModel?

    private let checkerLayer = CALayer()
    private let imageLayer = CALayer()
    private let strokeLayer = CAShapeLayer()
    private let antsWhite = CAShapeLayer()
    private let antsBlack = CAShapeLayer()
    private let cursorOuter = CAShapeLayer()
    private let cursorInner = CAShapeLayer()

    /// Logical image size in pixels.
    private var imageSize = CGSize.zero
    /// Points per image pixel.
    private var scale = 1.0
    /// View position of the image's top-left corner.
    private var origin = CGPoint.zero
    private var autoFit = true
    private var lastFitRequest = -1

    private enum Drag {
        case none
        case pan(last: CGPoint)
        case newSelection(anchor: ImagePoint)
        case moveSelection(start: ImagePoint, original: IRect)
        case stroke
    }
    private var drag = Drag.none
    private var dragSelection: IRect?
    private var strokePoints: [ImagePoint] = []
    private var spaceHeld = false
    private var mouseInside = false
    private var lastMouse = CGPoint.zero
    private var resignKeyObserver: NSObjectProtocol?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        setUpLayers()
    }

    required init?(coder: NSCoder) {
        fatalError("CanvasView is created in code")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func setUpLayers() {
        guard let root = layer else { return }
        root.backgroundColor = Design.canvasBackground.cgColor
        root.masksToBounds = true
        checkerLayer.backgroundColor = Checkerboard.color
        imageLayer.contentsGravity = .resize
        imageLayer.minificationFilter = .trilinear
        imageLayer.magnificationFilter = .nearest
        strokeLayer.fillColor = nil
        strokeLayer.strokeColor = Design.strokeOverlay.cgColor
        strokeLayer.lineCap = .round
        strokeLayer.lineJoin = .round
        antsWhite.fillColor = nil
        antsWhite.strokeColor = NSColor.white.cgColor
        antsWhite.lineWidth = 1
        antsBlack.fillColor = nil
        antsBlack.strokeColor = NSColor.black.cgColor
        antsBlack.lineWidth = 1
        antsBlack.lineDashPattern = [4, 4]
        cursorOuter.fillColor = nil
        cursorOuter.strokeColor = NSColor.black.withAlphaComponent(0.8).cgColor
        cursorOuter.lineWidth = 1
        cursorInner.fillColor = nil
        cursorInner.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        cursorInner.lineWidth = 1
        for l in [checkerLayer, imageLayer, strokeLayer, antsWhite, antsBlack, cursorOuter, cursorInner] {
            l.actions = ["position": NSNull(), "bounds": NSNull(), "path": NSNull(), "contents": NSNull(),
                         "frame": NSNull(), "hidden": NSNull(), "lineWidth": NSNull()]
            root.addSublayer(l)
        }
        startMarchingAnts()
    }

    private func startMarchingAnts() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let anim = CABasicAnimation(keyPath: "lineDashPhase")
        anim.fromValue = 0
        anim.toValue = 8
        anim.duration = 0.6
        anim.repeatCount = .infinity
        antsBlack.add(anim, forKey: "march")
    }

    // MARK: - Model → canvas

    /// Called by the SwiftUI wrapper whenever the model's displayed image or selection changes.
    func update(image: CGImage?, size: CGSize, fitRequest: Int, selection: IRect?) {
        if (imageLayer.contents as AnyObject?) !== (image as AnyObject?) {
            imageLayer.contents = image
            checkerLayer.isHidden = image == nil
        }
        if size != imageSize {
            imageSize = size
            autoFit = true
        }
        if fitRequest != lastFitRequest {
            lastFitRequest = fitRequest
            autoFit = true
        }
        if case .newSelection = drag {} else if case .moveSelection = drag {} else { dragSelection = nil }
        layoutCanvas()
        drawSelection(dragSelection ?? selection)
    }

    override func layout() {
        super.layout()
        layoutCanvas()
    }

    private func layoutCanvas() {
        guard imageSize.width > 0, bounds.width > 0 else { return }
        if autoFit { fit() }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let frame = CGRect(x: origin.x, y: origin.y, width: imageSize.width * scale, height: imageSize.height * scale)
        imageLayer.frame = frame
        checkerLayer.frame = frame
        imageLayer.magnificationFilter = zoomPercent >= 100 ? .nearest : .linear
        CATransaction.commit()
        drawSelection(dragSelection ?? model?.selection)
        drawStroke()
        drawBrushCursor()
        publishZoom()
    }

    private var backingScale: Double { Double(window?.backingScaleFactor ?? 2) }
    private var zoomPercent: Double { scale * backingScale * 100 }

    private func publishZoom() {
        let z = (zoomPercent * 10).rounded() / 10
        if model?.zoomPercent != z { model?.zoomPercent = z }
    }

    // MARK: - Geometry

    private func imagePoint(_ p: CGPoint) -> ImagePoint {
        ImagePoint(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale)
    }

    private func viewPoint(_ q: ImagePoint) -> CGPoint {
        CGPoint(x: origin.x + q.x * scale, y: origin.y + q.y * scale)
    }

    private func fit() {
        let pad = 24.0
        let s = min((bounds.width - 2 * pad) / imageSize.width, (bounds.height - 2 * pad) / imageSize.height)
        scale = max(0.001, s)
        origin = CGPoint(x: (bounds.width - imageSize.width * scale) / 2,
                         y: (bounds.height - imageSize.height * scale) / 2)
    }

    /// Zooms so `anchor` (a view point) stays over the same image pixel.
    private func setScale(_ newScale: Double, anchor: CGPoint) {
        let minScale = 0.01 / backingScale
        let maxScale = 64 / backingScale
        let s = min(max(newScale, minScale), maxScale)
        let q = imagePoint(anchor)
        scale = s
        origin = CGPoint(x: anchor.x - q.x * s, y: anchor.y - q.y * s)
        autoFit = false
        clampPan()
        layoutCanvas()
    }

    /// Keeps at least a margin of the image on screen.
    private func clampPan() {
        let w = imageSize.width * scale, h = imageSize.height * scale
        let margin = 80.0
        if w <= bounds.width {
            origin.x = min(max(origin.x, 0), bounds.width - w)
        } else {
            origin.x = min(max(origin.x, bounds.width - w - margin), margin)
        }
        if h <= bounds.height {
            origin.y = min(max(origin.y, 0), bounds.height - h)
        } else {
            origin.y = min(max(origin.y, bounds.height - h - margin), margin)
        }
    }

    private var viewCenter: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    // Photoshop-style zoom steps (percent of device pixels).
    private static let zoomSteps: [Double] = [1, 2, 3, 5, 8, 12.5, 16.7, 25, 33.3, 50, 66.7, 100, 150, 200, 300,
                                              400, 600, 800, 1200, 1600, 3200]

    func zoomIn() {
        let next = Self.zoomSteps.first { $0 > zoomPercent + 0.1 } ?? 3200
        setScale(next / 100 / backingScale, anchor: viewCenter)
    }

    func zoomOut() {
        let next = Self.zoomSteps.last { $0 < zoomPercent - 0.1 } ?? 1
        setScale(next / 100 / backingScale, anchor: viewCenter)
    }

    func zoomToFit() {
        autoFit = true
        layoutCanvas()
    }

    func zoomActualPixels() {
        setScale(1 / backingScale, anchor: viewCenter)
    }

    // MARK: - Test support

    /// Window coordinates of an image pixel (used by the self-test to aim synthetic mouse events).
    func windowPoint(forImage q: ImagePoint) -> CGPoint {
        convert(viewPoint(q), to: nil)
    }

    /// Zooms to `percent` with the given image point in the middle of the view.
    func center(on q: ImagePoint, percent: Double) {
        scale = percent / 100 / backingScale
        origin = CGPoint(x: bounds.midX - q.x * scale, y: bounds.midY - q.y * scale)
        autoFit = false
        layoutCanvas()
    }

    // MARK: - Overlays

    private func viewRect(_ r: IRect) -> CGRect {
        let a = viewPoint(ImagePoint(x: Double(r.x), y: Double(r.y)))
        let b = viewPoint(ImagePoint(x: Double(r.maxX), y: Double(r.maxY)))
        return CGRect(x: a.x.rounded() + 0.5, y: a.y.rounded() + 0.5,
                      width: (b.x - a.x).rounded(), height: (b.y - a.y).rounded())
    }

    private func drawSelection(_ r: IRect?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let r, r.w > 0, r.h > 0 {
            let path = CGPath(rect: viewRect(r), transform: nil)
            antsWhite.path = path
            antsBlack.path = path
        } else {
            antsWhite.path = nil
            antsBlack.path = nil
        }
        CATransaction.commit()
    }

    private func drawStroke() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if strokePoints.isEmpty {
            strokeLayer.path = nil
        } else {
            let path = CGMutablePath()
            let pts = strokePoints.map(viewPoint)
            path.move(to: pts[0])
            if pts.count == 1 { path.addLine(to: pts[0]) }
            for p in pts.dropFirst() { path.addLine(to: p) }
            strokeLayer.path = path
            strokeLayer.lineWidth = (model?.brushSize ?? 10) * scale
        }
        CATransaction.commit()
    }

    func drawBrushCursor() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let showsBrush = mouseInside && !spaceHeld && model?.tool == .heal && model?.mode == .editing
        if showsBrush, let size = model?.brushSize {
            let r = max(1.5, size * scale / 2)
            cursorOuter.path = CGPath(ellipseIn: CGRect(x: lastMouse.x - r, y: lastMouse.y - r, width: 2 * r, height: 2 * r), transform: nil)
            let ri = max(0.5, r - 1)
            cursorInner.path = CGPath(ellipseIn: CGRect(x: lastMouse.x - ri, y: lastMouse.y - ri, width: 2 * ri, height: 2 * ri), transform: nil)
        } else {
            cursorOuter.path = nil
            cursorInner.path = nil
        }
        CATransaction.commit()
    }

    // MARK: - Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate],
                                       owner: self, userInfo: nil))
    }

    override func cursorUpdate(with event: NSEvent) {
        currentCursor().set()
    }

    private func currentCursor() -> NSCursor {
        if spaceHeld || model?.tool == .hand {
            if case .pan = drag { return .closedHand }
            return .openHand
        }
        return .crosshair
    }

    override func mouseEntered(with event: NSEvent) {
        mouseInside = true
        lastMouse = convert(event.locationInWindow, from: nil)
        drawBrushCursor()
    }

    override func mouseExited(with event: NSEvent) {
        mouseInside = false
        drawBrushCursor()
    }

    override func mouseMoved(with event: NSEvent) {
        lastMouse = convert(event.locationInWindow, from: nil)
        mouseInside = true
        drawBrushCursor()
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let model, model.mode == .editing || model.mode == .developing else { return }
        let p = convert(event.locationInWindow, from: nil)
        lastMouse = p
        if spaceHeld || model.tool == .hand || model.mode == .developing {
            drag = .pan(last: p)
            currentCursor().set()
            return
        }
        guard model.canEdit else { NSSound.beep(); return }
        let q = imagePoint(p)
        switch model.tool {
        case .select:
            if let sel = model.selection, sel.contains(x: Int(q.x), y: Int(q.y)) {
                drag = .moveSelection(start: q, original: sel)
            } else {
                drag = .newSelection(anchor: clampToImage(q))
            }
        case .heal:
            strokePoints = [q]
            drag = .stroke
            drawStroke()
        case .magicEraser:
            Task { await model.magicErase(at: q) }
        case .hand:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let model else { return }
        let p = convert(event.locationInWindow, from: nil)
        lastMouse = p
        let q = imagePoint(p)
        switch drag {
        case .none:
            break
        case .pan(let last):
            origin.x += p.x - last.x
            origin.y += p.y - last.y
            autoFit = false
            clampPan()
            drag = .pan(last: p)
            layoutCanvas()
        case .newSelection(let anchor):
            dragSelection = selectionRect(from: anchor, to: clampToImage(q),
                                          square: event.modifierFlags.contains(.shift), ratio: model.selectionRatio.value)
            drawSelection(dragSelection)
        case .moveSelection(let start, let original):
            var r = original
            r.x = min(max(original.x + Int((q.x - start.x).rounded()), 0), Int(imageSize.width) - r.w)
            r.y = min(max(original.y + Int((q.y - start.y).rounded()), 0), Int(imageSize.height) - r.h)
            dragSelection = r
            drawSelection(r)
        case .stroke:
            if let last = strokePoints.last {
                let d = hypot(q.x - last.x, q.y - last.y)
                if d >= max(1, model.brushSize / 8) {
                    strokePoints.append(q)
                    drawStroke()
                }
            }
            drawBrushCursor()
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let model else { return }
        let finished = drag
        drag = .none
        switch finished {
        case .newSelection:
            if let r = dragSelection, r.w >= 2, r.h >= 2 {
                model.selection = r
            } else {
                model.deselect()
            }
            dragSelection = nil
        case .moveSelection:
            if let r = dragSelection { model.selection = r }
            dragSelection = nil
        case .stroke:
            let points = strokePoints
            Task {
                await model.heal(points: points)
                strokePoints = []
                drawStroke()
            }
        case .pan, .none:
            break
        }
        currentCursor().set()
    }

    private func clampToImage(_ q: ImagePoint) -> ImagePoint {
        ImagePoint(x: min(max(q.x, 0), imageSize.width), y: min(max(q.y, 0), imageSize.height))
    }

    /// Rectangle from the drag anchor to the current point, optionally held to an aspect ratio.
    private func selectionRect(from a: ImagePoint, to b: ImagePoint, square: Bool, ratio: Double?) -> IRect {
        var dx = b.x - a.x, dy = b.y - a.y
        if let r = square ? 1.0 : ratio {
            // Grow to the ratio, but no further than the image edge in the drag direction,
            // so clipping to the image never changes the ratio.
            let roomX = dx < 0 ? a.x : imageSize.width - a.x
            let roomY = dy < 0 ? a.y : imageSize.height - a.y
            let w = min(max(abs(dx), abs(dy) * r), roomX, roomY * r)
            dx = w * (dx < 0 ? -1 : 1)
            dy = w / r * (dy < 0 ? -1 : 1)
        }
        // Snap each edge to the nearest pixel boundary, like the marquee tool does.
        let x0 = Int(min(a.x, a.x + dx).rounded()), y0 = Int(min(a.y, a.y + dy).rounded())
        let x1 = Int(max(a.x, a.x + dx).rounded()), y1 = Int(max(a.y, a.y + dy).rounded())
        let r = IRect(x: x0, y: y0, w: x1 - x0, h: y1 - y0)
        return r.intersection(IRect(x: 0, y: 0, w: Int(imageSize.width), h: Int(imageSize.height)))
    }

    // MARK: - Scroll, pinch, keys

    override func scrollWheel(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
            setScale(scale * exp(delta * 0.01), anchor: p)
            return
        }
        let k = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
        origin.x += event.scrollingDeltaX * k
        origin.y += event.scrollingDeltaY * k
        autoFit = false
        clampPan()
        layoutCanvas()
    }

    override func magnify(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        setScale(scale * (1 + event.magnification), anchor: p)
    }

    override func keyDown(with event: NSEvent) {
        guard let model else { super.keyDown(with: event); return }
        if event.keyCode == 49 { // space
            if !spaceHeld {
                spaceHeld = true
                currentCursor().set()
                drawBrushCursor()
            }
            return
        }
        // A floating filter dialog keeps its keys even after a click or pan gave the canvas focus.
        let floatingDialog = model.dialog?.floatsOverCanvas == true
        if event.keyCode == 53 { // escape: cancel the dialog, else deselect
            if floatingDialog {
                Task { await model.cancelPreview() }
            } else {
                model.deselect()
            }
            return
        }
        if event.keyCode == 36 || event.keyCode == 76 { // return / enter: apply the dialog, else crop to selection
            if floatingDialog {
                if let op = model.currentFilterOp { Task { await model.commitFilter(op) } }
            } else if model.tool == .select, model.selection != nil {
                Task { await model.cropToSelection() }
            }
            return
        }
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        guard mods.isEmpty, let ch = event.charactersIgnoringModifiers?.lowercased().first else {
            super.keyDown(with: event)
            return
        }
        switch ch {
        case "[":
            model.brushSize = max(Design.minBrushSize, (model.brushSize * 0.85).rounded())
            drawBrushCursor()
        case "]":
            model.brushSize = min(Design.maxBrushSize, max(model.brushSize + 1, (model.brushSize * 1.15).rounded()))
            drawBrushCursor()
        default:
            if let tool = Tool.allCases.first(where: { $0.shortcut == ch }) {
                model.tool = tool
                currentCursor().set()
                drawBrushCursor()
            } else {
                super.keyDown(with: event)
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            releaseSpace()
            return
        }
        super.keyUp(with: event)
    }

    /// Space released while another window or app has the keyboard never reaches us, so the temporary
    /// Hand is also dropped whenever this view or its window loses key status.
    private func releaseSpace() {
        guard spaceHeld else { return }
        spaceHeld = false
        currentCursor().set()
        drawBrushCursor()
    }

    override func resignFirstResponder() -> Bool {
        releaseSpace()
        return super.resignFirstResponder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resignKeyObserver { NotificationCenter.default.removeObserver(resignKeyObserver) }
        resignKeyObserver = nil
        guard let window else { return }
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseSpace() }
        }
    }
}
