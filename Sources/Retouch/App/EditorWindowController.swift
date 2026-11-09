import AppKit
import Observation
import RetouchCore
import SwiftUI

/// One window per image. Receives the menu commands for its image and asks before closing
/// with unexported changes.
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let model: EditorModel
    private let onClose: (EditorWindowController) -> Void
    private var closeConfirmed = false
    private var filterPanel: NSPanel?
    private var dialogWatcher: Task<Void, Never>?

    /// The dialog open over this window right now: a floating filter panel or a sheet.
    var dialogWindow: NSWindow? { filterPanel ?? window?.attachedSheet }

    init(url: URL, onClose: @escaping (EditorWindowController) -> Void) {
        model = EditorModel(fileURL: url)
        self.onClose = onClose
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1320, height: 860),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = url.lastPathComponent
        window.representedURL = url
        window.minSize = NSSize(width: 820, height: 520)
        window.isRestorable = false
        window.tabbingMode = .preferred
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: EditorView(model: model))
        model.window = window
        watchDialog()
        Task { await model.start() }
    }

    required init?(coder: NSCoder) {
        fatalError("EditorWindowController is created in code")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if let canvas = model.canvas { window?.makeFirstResponder(canvas) }
    }

    // MARK: - Floating filter panel

    private func watchDialog() {
        let model = self.model
        dialogWatcher = Task { [weak self] in
            for await dialog in Observations({ model.dialog }) {
                self?.presentFilterPanel(for: dialog?.floatsOverCanvas == true ? dialog : nil)
            }
        }
    }

    /// Filters with a live preview open in a panel floating over the canvas rather than a sheet:
    /// macOS dims the window behind a sheet, which makes sharpening impossible to judge.
    private func presentFilterPanel(for dialog: ActiveDialog?) {
        if let filterPanel {
            window?.removeChildWindow(filterPanel)
            filterPanel.orderOut(nil)
            self.filterPanel = nil
            Task { await model.dialogDidClose() }
        }
        guard let dialog, let window else { return }
        let hosting = NSHostingView(rootView: DialogHostView(model: model, dialog: dialog))
        hosting.safeAreaRegions = [] // the title bar is hidden; don't leave an empty strip for it
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                            styleMask: [.titled, .fullSizeContentView, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isRestorable = false
        panel.contentView = hosting
        panel.setFrameOrigin(filterPanelOrigin(for: panel.frame.size, in: window))
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        filterPanel = panel
    }

    /// Top-right corner of the canvas, inset, so the panel covers as little of the photo as it can.
    private func filterPanelOrigin(for size: NSSize, in window: NSWindow) -> NSPoint {
        let area: NSRect
        if let canvas = model.canvas {
            area = window.convertToScreen(canvas.convert(canvas.bounds, to: nil))
        } else {
            area = window.frame
        }
        return NSPoint(x: area.maxX - size.width - Design.floatingPanelInset,
                       y: area.maxY - size.height - Design.floatingPanelInset)
    }

    // MARK: - Closing

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closeConfirmed || !model.hasUnexportedWork { return true }
        let alert = NSAlert()
        alert.messageText = "Export the changes you made to “\(model.fileURL.lastPathComponent)”?"
        alert.informativeText = "Your changes will be lost if you don't export them."
        alert.addButton(withTitle: "Export…")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Export")
        alert.beginSheetModal(for: sender) { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                switch response {
                case .alertFirstButtonReturn:
                    // The window closes on its own once this export succeeds.
                    self.model.closeAfterExport = true
                    self.model.dialog = .export
                case .alertThirdButtonReturn:
                    self.closeConfirmed = true
                    sender.performClose(nil)
                default: break
                }
            }
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        dialogWatcher?.cancel()
        onClose(self)
    }

    // MARK: - Menu commands

    @objc func saveImage(_ sender: Any?) { model.save() }
    @objc func exportImage(_ sender: Any?) { model.dialog = .export }
    @objc func revealExport(_ sender: Any?) {
        guard let url = model.lastExport?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    @objc func undoEdit(_ sender: Any?) { Task { await model.undo() } }
    @objc func redoEdit(_ sender: Any?) { Task { await model.redo() } }
    @objc func autoTone(_ sender: Any?) { Task { await model.autoAdjust(.tone) } }
    @objc func autoContrast(_ sender: Any?) { Task { await model.autoAdjust(.contrast) } }
    @objc func autoColor(_ sender: Any?) { Task { await model.autoAdjust(.color) } }
    @objc func hueSaturation(_ sender: Any?) { model.dialog = .hueSaturation }
    @objc func imageSize(_ sender: Any?) { model.dialog = .imageSize }
    @objc func cropToSelection(_ sender: Any?) { Task { await model.cropToSelection() } }
    @objc func rotate180(_ sender: Any?) { Task { await model.rotate(degrees: 180) } }
    @objc func rotate90CW(_ sender: Any?) { Task { await model.rotate(degrees: 90) } }
    @objc func rotate90CCW(_ sender: Any?) { Task { await model.rotate(degrees: -90) } }
    @objc func rotateArbitrary(_ sender: Any?) { model.dialog = .rotate }
    @objc func sharpen(_ sender: Any?) { Task { await model.commitFilter(.sharpen) } }
    @objc func unsharpMask(_ sender: Any?) { model.dialog = .unsharpMask }
    @objc func crystallize(_ sender: Any?) { model.dialog = .crystallize }
    @objc func mosaic(_ sender: Any?) { model.dialog = .mosaic }
    @objc func pointillize(_ sender: Any?) { model.dialog = .pointillize }
    @objc override func selectAll(_ sender: Any?) { model.selectAll() }
    @objc func deselectPixels(_ sender: Any?) { model.deselect() }
    @objc func zoomIn(_ sender: Any?) { model.canvas?.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { model.canvas?.zoomOut() }
    @objc func zoomToFit(_ sender: Any?) { model.canvas?.zoomToFit() }
    @objc func zoomActual(_ sender: Any?) { model.canvas?.zoomActualPixels() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else { return true }
        switch action {
        case #selector(undoEdit(_:)):
            menuItem.title = model.undoTitle
            return model.canUndo
        case #selector(redoEdit(_:)):
            menuItem.title = model.redoTitle
            return model.canRedo
        case #selector(revealExport(_:)):
            return model.lastExport != nil
        case #selector(cropToSelection(_:)):
            return model.canEdit && model.selection != nil
        case #selector(deselectPixels(_:)):
            return model.selection != nil && model.dialog == nil
        case #selector(zoomIn(_:)), #selector(zoomOut(_:)), #selector(zoomToFit(_:)), #selector(zoomActual(_:)):
            // Zoom stays available while a filter preview floats over the canvas.
            return model.displayImage != nil && (model.dialog == nil || model.dialog?.floatsOverCanvas == true)
        case #selector(selectAll(_:)):
            return model.mode == .editing && model.dialog == nil
        default:
            return model.canEdit
        }
    }
}
