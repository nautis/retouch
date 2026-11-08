import AppKit
import Observation
import RetouchCore
import UniformTypeIdentifiers

/// Everything one editor window knows: the image, the history, the tool settings, and the edits.
@MainActor
@Observable
final class EditorModel {
    let fileURL: URL
    let isRaw: Bool

    private(set) var mode: EditorMode = .loading
    /// The committed image. Nil until the file has loaded (or the RAW has been developed).
    private(set) var buffer: PixelBuffer?
    /// What the canvas shows: the committed image, a filter preview, or the RAW develop preview.
    private(set) var displayImage: CGImage?
    /// Logical size of the image on the canvas in pixels (the RAW's native size while developing).
    private(set) var imageSize = CGSize.zero
    /// Bumped when the canvas should re-fit the image (new image, crop, rotate, resize).
    private(set) var fitRequest = 0

    var tool = Tool.heal
    var brushSize = 40.0
    var tolerance = 32.0
    var antiAlias = true
    var contiguous = true
    var selectionRatio = SelectionRatio.free
    var selection: IRect?

    var dialog: ActiveDialog?
    var errorMessage: String?
    /// What's running, for the status bar: an edit, export or develop step, or a dialog's live preview.
    var busyMessage: String? { busy ?? (previewsRunning > 0 ? "Previewing…" : nil) }
    /// Set while an edit, export or develop step runs; no other edit starts until it lands.
    private var busy: String?
    /// Live previews still rendering. They never block an edit, so OK can land while one is in flight.
    private var previewsRunning = 0
    /// True from Open Image until the full-resolution develop lands.
    private(set) var isFinishingDevelop = false
    /// Set when the user picks Export… in the close alert: close the window once that export succeeds.
    var closeAfterExport = false
    var zoomPercent = 100.0

    var rawSettings: RawSettings {
        didSet {
            guard rawSettings != oldValue else { return }
            UserDefaults.standard.set(rawSettings.look.rawValue, forKey: Self.lookKey)
            UserDefaults.standard.set(rawSettings.lensCorrection, forKey: Self.lensKey)
            scheduleDevelopPreview()
        }
    }
    private(set) var rawInfo: RawInfo?

    struct LastExport {
        var url: URL
        var options: ExportOptions
        /// Image size at export time: the same size now means Save repeats the export exactly.
        var sourceWidth: Int
        var sourceHeight: Int
    }
    /// Last export, so Save (Cmd-S) can write the same file again without asking.
    private(set) var lastExport: LastExport?

    @ObservationIgnored let history = History()
    /// Changes whenever the undo stack changes, so menus and the edited dot refresh.
    private(set) var historyVersion = 0
    private var savedStepID: UUID?

    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored weak var canvas: CanvasView?
    @ObservationIgnored private var developTask: Task<Void, Never>?
    @ObservationIgnored private var pendingPreview: (op: FilterOp, rect: IRect, bytes: [UInt8])?
    /// The settings the open filter dialog shows, so Return on the canvas applies them.
    @ObservationIgnored private(set) var currentFilterOp: FilterOp?
    @ObservationIgnored private var displayGeneration = 0
    var showPreview = true {
        didSet { if showPreview != oldValue { refreshPreviewVisibility() } }
    }

    private static let lookKey = "rawLook"
    private static let lensKey = "rawLensCorrection"

    init(fileURL: URL) {
        self.fileURL = fileURL.standardizedFileURL
        isRaw = ImageFiles.isRaw(fileURL)
        let look = RawLook(rawValue: UserDefaults.standard.string(forKey: Self.lookKey) ?? "") ?? .standard
        let lens = UserDefaults.standard.object(forKey: Self.lensKey) as? Bool ?? true
        rawSettings = RawSettings(look: look, lensCorrection: lens)
    }

    // MARK: - State

    var isDirty: Bool {
        _ = historyVersion
        return history.currentStateID != savedStepID
    }

    /// Unexported edits, or an edit that is still landing: both are lost if the window closes now.
    var hasUnexportedWork: Bool { isDirty || (mode == .editing && busy != nil) }

    var canEdit: Bool { mode == .editing && busy == nil && dialog == nil && buffer != nil }
    var canUndo: Bool { _ = historyVersion; return canEdit && history.canUndo }
    var canRedo: Bool { _ = historyVersion; return canEdit && history.canRedo }
    var undoTitle: String { _ = historyVersion; return history.undoName.map { "Undo \($0)" } ?? "Undo" }
    var redoTitle: String { _ = historyVersion; return history.redoName.map { "Redo \($0)" } ?? "Redo" }

    /// The area edits apply to: the selection, or the whole image.
    var editRect: IRect? {
        guard let b = buffer else { return nil }
        return selection?.intersection(b.bounds) ?? b.bounds
    }

    // MARK: - Opening

    func start() async {
        if isRaw {
            do {
                let info = try await Work.rawInfo(fileURL)
                rawInfo = info
                imageSize = CGSize(width: info.width, height: info.height)
                mode = .developing
                scheduleDevelopPreview(immediately: true)
            } catch {
                mode = .failed(error.localizedDescription)
            }
        } else {
            busy = "Opening…"
            do {
                let b = try await Work.loadRaster(fileURL)
                busy = nil
                await install(b, refit: true)
                mode = .editing
            } catch {
                busy = nil
                mode = .failed(error.localizedDescription)
            }
        }
    }

    /// Re-renders the small RAW preview after a look/lens change (the latest change wins).
    /// Nothing starts once Open Image is pressed: a late preview would replace the full-resolution image.
    private func scheduleDevelopPreview(immediately: Bool = false) {
        guard mode == .developing, !isFinishingDevelop else { return }
        developTask?.cancel()
        let settings = rawSettings
        let url = fileURL
        developTask = Task {
            if !immediately { try? await Task.sleep(for: .milliseconds(60)) }
            guard !Task.isCancelled else { return }
            busy = "Rendering preview…"
            do {
                let preview = try await Work.develop(url, settings: settings, maxDimension: 2400)
                guard !Task.isCancelled else { return }
                let image = await Work.displayImage(preview)
                guard !Task.isCancelled else { return }
                displayImage = image
                if fitRequest == 0 { fitRequest += 1 }
            } catch {
                errorMessage = error.localizedDescription
            }
            busy = nil
        }
    }

    /// Develops the RAW at full resolution with the chosen look and starts editing.
    func finishDevelop() async {
        guard mode == .developing, !isFinishingDevelop else { return }
        isFinishingDevelop = true
        developTask?.cancel()
        busy = "Developing full resolution…"
        do {
            let b = try await Work.develop(fileURL, settings: rawSettings, maxDimension: nil)
            busy = nil
            await install(b, refit: false)
            mode = .editing
        } catch {
            busy = nil
            errorMessage = error.localizedDescription
        }
        isFinishingDevelop = false
    }

    // MARK: - Display

    /// Sets the committed buffer and refreshes what the canvas shows.
    private func install(_ b: PixelBuffer, refit: Bool) async {
        let sizeChanged = buffer.map { $0.width != b.width || $0.height != b.height } ?? true
        buffer = b
        imageSize = CGSize(width: b.width, height: b.height)
        if let s = selection, s.intersection(b.bounds) != s { selection = nil }
        await showImage(of: b)
        if refit || (sizeChanged && mode == .editing) { fitRequest += 1 }
    }

    private func showImage(of b: PixelBuffer) async {
        displayGeneration += 1
        let generation = displayGeneration
        let image = await Work.displayImage(b)
        if generation == displayGeneration { displayImage = image }
    }

    private func refreshDisplay() async {
        if let b = buffer { await showImage(of: b) }
    }

    private func didChangeHistory() {
        historyVersion += 1
        // Set synchronously so the close button's dot is right the moment an edit lands or an export finishes.
        window?.isDocumentEdited = isDirty
    }

    // MARK: - Edits

    /// Runs `work` with a busy message, then records its result as one undoable step.
    private func runRegionEdit(_ name: String, rect: IRect,
                               _ work: @escaping @Sendable (PixelBuffer) async -> [UInt8]) async {
        guard canEdit, var b = buffer else { return }
        busy = "\(name)…"
        let bytes = await work(b)
        history.applyRegion(name, rect: rect, after: bytes, to: &b)
        busy = nil
        buffer = b
        didChangeHistory()
        await refreshDisplay()
    }

    private func runWholeEdit(_ name: String, clearSelection: Bool = true,
                              _ work: @escaping @Sendable (PixelBuffer) async -> PixelBuffer) async {
        guard canEdit, var b = buffer else { return }
        busy = "\(name)…"
        let result = await work(b)
        history.applyWhole(name, newBuffer: result, to: &b)
        busy = nil
        if clearSelection { selection = nil }
        didChangeHistory()
        await install(b, refit: true)
    }

    func heal(points: [ImagePoint]) async {
        guard canEdit, let b = buffer,
              let mask = HealMask.stroke(points: points, diameter: brushSize, imageBounds: b.bounds) else { return }
        await runRegionEdit("Spot Healing", rect: mask.rect) { await Work.heal($0, mask: mask) }
    }

    func magicErase(at point: ImagePoint) async {
        guard canEdit, var b = buffer else { return }
        let x = Int(point.x), y = Int(point.y)
        guard b.bounds.contains(x: x, y: y) else { return }
        busy = "Magic Eraser…"
        let result = await Work.magicErase(b, x: x, y: y, tolerance: Int(tolerance),
                                           contiguous: contiguous, antiAlias: antiAlias)
        busy = nil
        guard let result else { return }
        history.applyRegion("Magic Eraser", rect: result.rect, after: result.pixels, to: &b)
        buffer = b
        didChangeHistory()
        await refreshDisplay()
    }

    func autoAdjust(_ kind: AutoAdjust) async {
        guard let rect = editRect else { return }
        await runRegionEdit(kind.historyName, rect: rect) { await Work.auto(kind, $0, rect: rect) }
    }

    func cropToSelection() async {
        guard let rect = selection, rect.w > 0, rect.h > 0 else { return }
        await runWholeEdit("Crop") { await Work.crop($0, to: rect) }
    }

    func rotate(degrees: Double) async {
        let name = switch degrees {
        case 90: "Rotate 90° Clockwise"
        case -90: "Rotate 90° Counter Clockwise"
        case 180: "Rotate 180°"
        default: "Rotate Canvas"
        }
        await runWholeEdit(name) { await Work.rotate($0, degrees: degrees) }
    }

    func resize(width: Int, height: Int) async {
        guard let b = buffer, width > 0, height > 0, width != b.width || height != b.height else { return }
        await runWholeEdit("Image Size") { await Work.resize($0, width: width, height: height) }
    }

    func selectAll() {
        guard let b = buffer, mode == .editing, dialog == nil else { return }
        selection = b.bounds
    }

    func deselect() {
        // A preview is computed for the current selection; keep it fixed until the dialog closes.
        guard dialog == nil else { return }
        selection = nil
    }

    func undo() async {
        guard canUndo, var b = buffer else { return }
        let before = (b.width, b.height)
        history.undo(&b)
        didChangeHistory()
        await install(b, refit: before != (b.width, b.height))
    }

    func redo() async {
        guard canRedo, var b = buffer else { return }
        let before = (b.width, b.height)
        history.redo(&b)
        didChangeHistory()
        await install(b, refit: before != (b.width, b.height))
    }

    // MARK: - Filter previews

    /// Renders `op` into the canvas without committing it. Called as the dialog's sliders move; SwiftUI
    /// cancels the previous call's task, and a cancelled or orphaned preview is dropped when it lands.
    func preview(_ op: FilterOp) async {
        currentFilterOp = op
        guard let b = buffer, let rect = editRect else { return }
        try? await Task.sleep(for: Design.previewDebounce)
        guard !Task.isCancelled else { return }
        previewsRunning += 1
        let bytes = await Work.filter(op, b, rect: rect)
        previewsRunning -= 1
        guard !Task.isCancelled, dialog != nil else { return }
        pendingPreview = (op, rect, bytes)
        await refreshPreviewImage()
    }

    private func refreshPreviewImage() async {
        guard var b = buffer else { return }
        if showPreview, let p = pendingPreview {
            b.writeRegion(p.rect, p.bytes)
        }
        await showImage(of: b)
    }

    private func refreshPreviewVisibility() {
        Task { await refreshPreviewImage() }
    }

    func commitFilter(_ op: FilterOp) async {
        guard let rect = editRect else { return }
        // A finished preview of these exact settings is the result; don't render it twice.
        let reuse = pendingPreview.flatMap { $0.op == op && $0.rect == rect ? $0.bytes : nil }
        pendingPreview = nil
        currentFilterOp = nil
        dialog = nil
        await runRegionEdit(op.historyName, rect: rect) { b in
            if let reuse { return reuse }
            return await Work.filter(op, b, rect: rect)
        }
    }

    /// Called when a dialog closes by any route (including Esc): drops an uncommitted preview.
    /// Leaves `busy` alone: an edit the OK button started may still be landing.
    func dialogDidClose() async {
        // A sheet reports its dismissal after its animation; by then the user may have opened the next
        // dialog, whose state this late call must not clear.
        guard dialog == nil else { return }
        currentFilterOp = nil
        guard pendingPreview != nil || !showPreview else { return }
        pendingPreview = nil
        showPreview = true
        await refreshDisplay()
    }

    func cancelPreview() async {
        pendingPreview = nil
        currentFilterOp = nil
        dialog = nil
        showPreview = true
        await refreshDisplay()
    }

    // MARK: - Export

    /// Suggested export file name: next to the original; RAW files get "<name>.jpg",
    /// other files "<name>-edited.<ext>" so the original is never the default target.
    func suggestedExportURL(format: ExportFormat) -> URL {
        let base = fileURL.deletingPathExtension().lastPathComponent
        let name = isRaw ? base : "\(base)-edited"
        return fileURL.deletingLastPathComponent().appending(path: "\(name).\(format.fileExtension)")
    }

    func defaultExportOptions() -> ExportOptions {
        if let last = lastExport, let b = buffer {
            var o = last.options
            if b.width == last.sourceWidth && b.height == last.sourceHeight {
                return o // same image size: repeat the last export exactly, a hand-set height included
            }
            let wasFullSize = o.width == last.sourceWidth && o.height == last.sourceHeight
            if wasFullSize || o.width <= 0 {
                o.width = b.width
                o.height = b.height
            } else {
                // The image changed size (crop, rotate): keep the export width, follow the new proportions.
                o.height = max(1, Int((Double(o.width) * Double(b.height) / Double(b.width)).rounded()))
            }
            return o
        }
        return ExportOptions(format: .jpeg, quality: 0.9, width: buffer?.width ?? 0, height: buffer?.height ?? 0)
    }

    /// Asks where to save, then writes the file.
    func chooseDestinationAndExport(_ options: ExportOptions) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [options.format.utType]
        panel.canCreateDirectories = true
        let suggested = lastExport?.url.deletingPathExtension().appendingPathExtension(options.format.fileExtension)
            ?? suggestedExportURL(format: options.format)
        panel.directoryURL = suggested.deletingLastPathComponent()
        panel.nameFieldStringValue = suggested.lastPathComponent
        panel.beginSheetModal(for: window) { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                guard response == .OK, let url = panel.url else {
                    self.closeAfterExport = false
                    return
                }
                await self.export(to: url, options: options)
            }
        }
    }

    /// Cmd-S: re-export to the last destination, or ask for one.
    func save() {
        guard canEdit else { return }
        if let last = lastExport {
            Task { await export(to: last.url, options: defaultExportOptions()) }
        } else {
            dialog = .export
        }
    }

    func export(to url: URL, options: ExportOptions) async {
        guard let b = buffer else { return }
        busy = "Exporting \(url.lastPathComponent)…"
        do {
            try await Work.export(b, to: url, options: options)
            lastExport = LastExport(url: url, options: options, sourceWidth: b.width, sourceHeight: b.height)
            savedStepID = history.currentStateID
            busy = nil
            didChangeHistory()
            if closeAfterExport {
                closeAfterExport = false
                window?.performClose(nil)
            }
        } catch {
            busy = nil
            closeAfterExport = false
            errorMessage = error.localizedDescription
        }
    }
}
