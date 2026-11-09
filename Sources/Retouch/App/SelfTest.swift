import AppKit
import ApplicationServices
import RetouchCore

/// End-to-end check of the real app: `Retouch --selftest <outdir> <image>`.
/// Opens the file (a raw file goes through the Camera Raw step first), drives the canvas with
/// synthetic mouse and key events (heal, select, magic eraser, dialogs), applies filters, undoes,
/// crops, rotates and exports, writing a window snapshot after each step and a PASS/FAIL log to
/// <outdir>/selftest.txt. Coordinates are fractions of the image, so any photo works.
/// Does nothing without the flag.
@MainActor
enum SelfTest {
    private static var log: [String] = []
    private static var failures = 0
    private static var outDir = URL(fileURLWithPath: NSTemporaryDirectory())

    /// Starts the test if the flag is present. Returns true when it did.
    static func runIfRequested() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--selftest"), args.count > i + 2 else { return false }
        outDir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let file = URL(fileURLWithPath: args[i + 2])
        Task { await run(file: file) }
        return true
    }

    private static func note(_ s: String) {
        log.append(s)
        print(s)
        fflush(stdout) // the log is read while the test runs, or after it is killed
    }

    private static func check(_ ok: Bool, _ what: String) {
        note((ok ? "PASS " : "FAIL ") + what)
        if !ok { failures += 1 }
    }

    private static func wait(_ what: String, timeout: Double = 30, _ condition: () -> Bool) async {
        if await !settles(within: timeout, condition) { check(false, "timed out waiting for \(what)") }
    }

    /// Polls until `condition` holds; false on timeout. Use directly for states too brief to be
    /// guaranteed observable (a preview that renders in a few milliseconds on a small image).
    private static func settles(within timeout: Double, _ condition: () -> Bool) async -> Bool {
        let start = Date.now
        while !condition() {
            if Date.now.timeIntervalSince(start) > timeout { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    private static func finish() -> Never {
        note(failures == 0 ? "SELFTEST PASSED" : "SELFTEST FAILED: \(failures)")
        try? log.joined(separator: "\n").write(to: outDir.appending(path: "selftest.txt"), atomically: true, encoding: .utf8)
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Snapshots

    /// Writes the window exactly as it is composited on screen (SwiftUI chrome and the canvas layers).
    /// `cacheDisplay` misses NSHostingView content and CGWindowListCreateImage is gone from the SDK,
    /// so this shells out to screencapture for the one window. Needs Screen Recording permission
    /// for whatever terminal launched the test.
    private static func snap(_ window: NSWindow, _ name: String) async {
        // Let the last SwiftUI/Core Animation commit reach the window server before capturing.
        try? await Task.sleep(for: .milliseconds(300))
        let url = outDir.appending(path: "\(name).png")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        do {
            try capture.run()
            capture.waitUntilExit()
        } catch {
            check(false, "snapshot \(name): \(error.localizedDescription)")
            return
        }
        check(capture.terminationStatus == 0 && FileManager.default.fileExists(atPath: url.path), "snapshot \(name).png")
    }

    // MARK: - Synthetic input

    private static func pressSaveFromOutside() -> Bool {
        let script = """
        tell application "System Events" to tell process "Retouch"
            set s to sheet 1 of window 1
            click button "Save" of splitter group 1 of s
        end tell
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let err = Pipe()
        p.standardError = err
        do { try p.run() } catch { note("osascript: \(error.localizedDescription)"); return false }
        p.waitUntilExit()
        let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 { note("osascript exit \(p.terminationStatus): \(msg)") }
        return p.terminationStatus == 0
    }

    private static func mouse(_ type: NSEvent.EventType, _ p: CGPoint, _ window: NSWindow) -> NSEvent? {
        NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
    }

    private static func key(_ keyCode: UInt16, _ chars: String, _ window: NSWindow) -> NSEvent? {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                         windowNumber: window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                         isARepeat: false, keyCode: keyCode)
    }

    private static func drag(_ canvas: CanvasView, _ window: NSWindow, from a: ImagePoint, to b: ImagePoint, steps: Int) {
        guard let down = mouse(.leftMouseDown, canvas.windowPoint(forImage: a), window) else { return }
        canvas.mouseDown(with: down)
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let q = ImagePoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            if let e = mouse(.leftMouseDragged, canvas.windowPoint(forImage: q), window) { canvas.mouseDragged(with: e) }
        }
        if let up = mouse(.leftMouseUp, canvas.windowPoint(forImage: b), window) { canvas.mouseUp(with: up) }
    }

    // MARK: - The test

    private static func run(file: URL) async {
        note("Retouch self-test on \(file.lastPathComponent)")
        AppDelegate.shared?.open(file)
        guard let controller = AppDelegate.shared?.editorControllers.last, let window = controller.window else {
            check(false, "editor window opened")
            finish()
        }
        let m = controller.model
        window.setContentSize(NSSize(width: 1400, height: 900))

        if ImageFiles.isRaw(file) {
            await wait("raw develop preview") { m.mode == .developing && m.displayImage != nil && m.busyMessage == nil }
            check(m.mode == .developing, "raw file opens in the Camera Raw step")
            await snap(window, "01-develop-standard")
            m.rawSettings.look = .vivid
            try? await Task.sleep(for: .milliseconds(150))
            await wait("vivid preview") { m.busyMessage == nil }
            await snap(window, "02-develop-vivid")
            m.rawSettings.look = .standard
            try? await Task.sleep(for: .milliseconds(150))
            await wait("standard preview") { m.busyMessage == nil }

            // Open Image: look changes while the full develop runs must not start a preview that would
            // replace the full-resolution image once it lands
            let finishing = Task { await m.finishDevelop() }
            await wait("finishing state", timeout: 5) { m.isFinishingDevelop }
            check(m.isFinishingDevelop, "Open Image enters the finishing state")
            m.rawSettings.look = .vivid
            await finishing.value
            check(!m.isFinishingDevelop && m.mode == .editing, "full develop finished")
            check(m.busyMessage == nil, "look change during the full develop started no preview")
            m.rawSettings.look = .standard
            let native = m.rawInfo.map { CGSize(width: $0.width, height: $0.height) }
            check(native == m.imageSize, "full-res image matches the raw size \(Int(m.imageSize.width))x\(Int(m.imageSize.height))")
        }
        await wait("editing") { m.mode == .editing && m.displayImage != nil && m.busyMessage == nil }
        try? await Task.sleep(for: .milliseconds(200))
        let w = Int(m.imageSize.width), h = Int(m.imageSize.height)
        check(w >= 200 && h >= 200, "image is \(w)x\(h) (the test needs at least 200x200)")
        await snap(window, "03-editing")
        guard let canvas = m.canvas else {
            check(false, "canvas exists")
            finish()
        }
        check(m.zoomPercent > 0, "fits on screen at \(m.zoomPercent)%")

        // Positions as fractions of the image, so the same test runs on any photo.
        func px(_ f: Double) -> Int { Int(Double(w) * f) }
        func py(_ f: Double) -> Int { Int(Double(h) * f) }
        func at(_ fx: Double, _ fy: Double) -> ImagePoint { ImagePoint(x: Double(px(fx)), y: Double(py(fy))) }

        // Pruned history keeps the window dirty: undoing every retained step is not the original image
        m.history.byteLimit = 1
        await m.autoAdjust(.tone)
        await m.autoAdjust(.color)
        check(m.history.undoStack.count == 1, "history pruned to the newest step (\(m.history.undoStack.count) kept)")
        await m.undo()
        check(m.isDirty && window.isDocumentEdited, "undoing all retained steps after pruning still counts as edited")
        m.history.byteLimit = 8 << 30

        // Heal: paint a stroke through synthetic mouse events
        m.tool = .heal
        m.brushSize = max(8, (Double(w) / 136).rounded())
        let healRect = IRect(x: px(0.61), y: py(0.30), w: px(0.07), h: py(0.06)).intersection(m.buffer!.bounds)
        let before = m.buffer?.copyRegion(healRect)
        drag(canvas, window, from: at(0.629, 0.329), to: at(0.665, 0.329), steps: 12)
        await wait("heal") { m.busyMessage == nil && m.history.undoName == "Spot Healing" }
        let after = m.buffer?.copyRegion(healRect)
        check(m.history.undoName == "Spot Healing", "mouse stroke recorded as Spot Healing")
        check(before != nil && before != after, "heal changed pixels under the stroke")
        check(m.isDirty, "window marked as edited after heal")
        canvas.center(on: at(0.647, 0.329), percent: 100)
        try? await Task.sleep(for: .milliseconds(100))
        await snap(window, "04-heal-100pct")
        await m.undo()
        await snap(window, "05-heal-undone-100pct")
        await m.redo()
        canvas.zoomToFit()

        // A stroke dragged off the bottom-right edge must heal the part inside the image, not crash
        drag(canvas, window, from: at(0.976, 0.97), to: at(1.05, 1.1), steps: 10)
        await wait("edge heal") { m.busyMessage == nil && m.history.undoStack.count == 2 }
        check(m.history.undoStack.count == 2, "stroke past the image edge is healed (\(m.history.undoStack.count) steps)")
        await m.undo()

        // A size-1 brush clicked on a pixel corner covers no pixel center: nothing happens, no crash
        m.brushSize = 1
        let corner = ImagePoint(x: Double(w / 2), y: Double(h / 2))
        drag(canvas, window, from: corner, to: corner, steps: 1)
        try? await Task.sleep(for: .milliseconds(300))
        await wait("empty stroke") { m.busyMessage == nil }
        check(m.history.undoStack.count == 1, "a stroke covering no pixel records nothing (\(m.history.undoStack.count) steps)")
        m.brushSize = max(8, (Double(w) / 136).rounded())

        // Rectangle select by dragging
        m.tool = .select
        let ax = px(0.244), ay = py(0.256), bx = px(0.635), by = py(0.695)
        drag(canvas, window, from: at(0.244, 0.256), to: at(0.635, 0.695), steps: 8)
        check(m.selection == IRect(x: ax, y: ay, w: bx - ax, h: by - ay), "drag made selection \(m.selection?.description ?? "nil")")
        // move the selection outline by dragging inside it
        let shift = max(2, px(0.012))
        let inside = ImagePoint(x: Double((ax + bx) / 2), y: Double((ay + by) / 2))
        drag(canvas, window, from: inside, to: ImagePoint(x: inside.x + Double(shift), y: inside.y + Double(shift)), steps: 4)
        check(m.selection?.x == ax + shift && m.selection?.y == ay + shift,
              "dragging inside moves the selection to \(m.selection?.description ?? "nil")")
        let movedSelection = m.selection
        await snap(window, "06-selection")

        // A 1:1 selection dragged past the right edge stays square
        m.selectionRatio = .square
        let rx = px(0.952)
        drag(canvas, window, from: at(0.952, 0.183), to: ImagePoint(x: Double(w), y: Double(py(0.366))), steps: 4)
        check(m.selection?.w == w - rx && m.selection?.h == w - rx,
              "1:1 selection clipped at the edge stays square (\(m.selection?.description ?? "nil"))")
        m.selectionRatio = .free
        m.selection = movedSelection

        // Unsharp Mask floats over the canvas with a live preview, then cancel
        m.dialog = .unsharpMask
        await wait("Unsharp Mask panel") { controller.dialogWindow != nil }
        await wait("preview", timeout: 10) { m.busyMessage == nil }
        check(controller.dialogWindow is NSPanel && window.attachedSheet == nil, "Unsharp Mask opens as a floating panel, not a sheet")
        await snap(window, "07-unsharp-dialog-canvas")
        if let panel = controller.dialogWindow { await snap(panel, "07-unsharp-dialog-panel") }
        await m.cancelPreview()
        await wait("panel closed") { controller.dialogWindow == nil }

        // Every other dialog opens over the editor, renders, and closes clean
        for dialog in [ActiveDialog.hueSaturation, .mosaic, .crystallize, .pointillize, .imageSize, .rotate, .export] {
            m.dialog = dialog
            await wait("\(dialog.rawValue) dialog") { controller.dialogWindow != nil }
            await wait("\(dialog.rawValue) preview", timeout: 15) { m.busyMessage == nil }
            if let dialogWindow = controller.dialogWindow { await snap(dialogWindow, "07-dialog-\(dialog.rawValue)") }
            await m.cancelPreview()
            await wait("\(dialog.rawValue) closed") { controller.dialogWindow == nil }
            check(m.dialog == nil && controller.dialogWindow == nil, "\(dialog.rawValue) dialog opened and closed")
        }

        // Return on the canvas applies the floating dialog with its current settings
        m.dialog = .unsharpMask
        await wait("Unsharp Mask panel for Return") { controller.dialogWindow != nil }
        await wait("dialog settings known", timeout: 5) { m.currentFilterOp != nil }
        try? await Task.sleep(for: .milliseconds(200))
        await wait("preview for Return", timeout: 15) { m.busyMessage == nil }
        window.makeFirstResponder(canvas)
        if let ret = key(36, "\r", window) { canvas.keyDown(with: ret) }
        await wait("Return applies", timeout: 30) { controller.dialogWindow == nil && m.busyMessage == nil }
        check(m.history.undoName == "Unsharp Mask", "Return on the canvas applies the floating filter (\(m.history.undoName ?? "nil"))")
        await m.undo()

        // Esc on the canvas cancels the floating dialog
        m.dialog = .unsharpMask
        await wait("Unsharp Mask panel for Esc") { controller.dialogWindow != nil }
        window.makeFirstResponder(canvas)
        if let esc = key(53, "\u{1B}", window) { canvas.keyDown(with: esc) }
        await wait("Esc cancels", timeout: 10) { controller.dialogWindow == nil && m.busyMessage == nil }
        check(m.dialog == nil && controller.dialogWindow == nil, "Esc on the canvas cancels the floating filter dialog")

        // OK while the preview is still rendering: the filter must apply and the window must stay editable
        m.deselect()
        m.dialog = .unsharpMask
        await wait("Unsharp Mask panel again") { controller.dialogWindow != nil }
        await wait("dialog settings known", timeout: 5) { m.currentFilterOp != nil }
        _ = await settles(within: 5) { m.busyMessage != nil } // catch it mid-render when the image is big enough
        await m.commitFilter(.unsharpMask(amount: 100, radius: 1, threshold: 0))
        await wait("commit after early OK", timeout: 60) { m.busyMessage == nil && controller.dialogWindow == nil }
        check(m.history.undoName == "Unsharp Mask", "OK during a running preview still applies the filter (\(m.history.undoName ?? "nil"))")
        check(m.canEdit, "window is editable after OK during a running preview")
        await m.undo()
        m.selection = movedSelection

        // Mosaic inside the selection
        await m.commitFilter(.mosaic(cellSize: max(4, px(0.01))))
        check(m.history.undoName == "Mosaic", "Mosaic applied to the selection")
        await snap(window, "08-mosaic")

        // Magic eraser click near the top-left corner
        m.tool = .magicEraser
        m.deselect()
        let ex = px(0.037), ey = py(0.055)
        let eraseAt = ImagePoint(x: Double(ex) + 0.5, y: Double(ey) + 0.5)
        if let down = mouse(.leftMouseDown, canvas.windowPoint(forImage: eraseAt), window),
           let up = mouse(.leftMouseUp, canvas.windowPoint(forImage: eraseAt), window) {
            canvas.mouseDown(with: down)
            canvas.mouseUp(with: up)
        }
        await wait("magic eraser") { m.busyMessage == nil && m.history.undoName == "Magic Eraser" }
        check(m.buffer?.pixels[(ey * w + ex) * 4 + 3] == 0, "clicked pixel is transparent")
        await snap(window, "09-magic-eraser")

        // Auto Tone on the whole image
        await m.autoAdjust(.tone)
        check(m.history.undoName == "Auto Tone", "Auto Tone recorded")

        // Undo three: Auto Tone, Magic Eraser, Mosaic
        await m.undo(); await m.undo(); await m.undo()
        check(m.history.undoName == "Spot Healing", "three undos leave Spot Healing on top (\(m.history.undoName ?? "nil"))")
        await snap(window, "10-after-undos")

        // Crop to a selection, then undo
        let crop = IRect(x: px(0.122), y: py(0.146), w: px(0.73), h: py(0.73))
        m.selection = crop
        await m.cropToSelection()
        check(m.imageSize == CGSize(width: crop.w, height: crop.h), "crop to selection gives \(crop.w)x\(crop.h)")
        try? await Task.sleep(for: .milliseconds(200))
        await snap(window, "11-cropped")
        await m.undo()
        check(m.imageSize == CGSize(width: w, height: h), "undo crop restores \(w)x\(h)")

        // Rotate 90 clockwise, then arbitrary 3 degrees
        await m.rotate(degrees: 90)
        check(m.imageSize == CGSize(width: h, height: w), "rotate 90 swaps dimensions")
        try? await Task.sleep(for: .milliseconds(200))
        await snap(window, "12-rotated")
        await m.undo()
        await m.rotate(degrees: 3)
        check(Int(m.imageSize.width) > w, "arbitrary rotate grows the canvas")
        await m.undo()

        // Image Size
        let rw = max(1, w / 5), rh = max(1, h / 5)
        await m.resize(width: rw, height: rh)
        check(m.imageSize == CGSize(width: rw, height: rh), "resize to \(rw)x\(rh)")
        await m.undo()

        // Export full size JPG, then the window is no longer dirty
        let url = outDir.appending(path: "selftest-export.jpg")
        try? FileManager.default.removeItem(at: url)
        await m.export(to: url, options: m.defaultExportOptions())
        let exported = (try? ImageFiles.loadRaster(url)).map { ($0.width, $0.height) }
        check(exported.map { $0 == (w, h) } ?? false, "exported JPG is \(w)x\(h)")
        check(!m.isDirty, "export clears the edited state")
        check(window.isDocumentEdited == false, "close button dot cleared")

        // Edit again: dirty, and Save (Cmd-S) re-exports to the same file
        await m.autoAdjust(.contrast)
        check(m.isDirty, "edited again after export")
        m.save()
        await wait("save") { m.busyMessage == nil && !m.isDirty }
        check(!m.isDirty, "Save re-exported to \(url.lastPathComponent)")

        // Save repeats a custom export size exactly, a hand-set height included
        let small = outDir.appending(path: "selftest-export-small.jpg")
        await m.export(to: small, options: ExportOptions(format: .jpeg, quality: 0.8, width: 800, height: 800))
        await m.autoAdjust(.tone)
        m.save()
        await wait("save small") { m.busyMessage == nil && !m.isDirty }
        let smallSize = (try? ImageFiles.loadRaster(small)).map { ($0.width, $0.height) }
        check(smallSize.map { $0 == (800, 800) } ?? false,
              "Save kept the 800x800 export size (\(smallSize.map { "\($0.0)x\($0.1)" } ?? "none"))")

        // The route a person takes: Export As… sheet, its Export… button, then the save sheet, then
        // Save. Nothing above goes through the save panel. The panel suggests the last export's
        // file (already in outDir); it is removed first so Save needs no replace confirmation.
        try? FileManager.default.removeItem(at: small)
        await m.autoAdjust(.tone)
        m.dialog = .export
        await wait("Export As sheet") { controller.dialogWindow != nil }
        try? await Task.sleep(for: .milliseconds(300))
        // Exactly what the sheet's Export… button does (ExportDialog.export): close the sheet, ask where.
        m.dialog = nil
        m.chooseDestinationAndExport(m.defaultExportOptions())
        let panelShown = await settles(within: 10) { window.attachedSheet is NSSavePanel }
        check(panelShown, "Export… opens the save sheet")
        if let panel = window.attachedSheet as? NSSavePanel {
            check(panel.nameFieldStringValue == small.lastPathComponent,
                  "save sheet suggests the last export's name (got \(panel.nameFieldStringValue))")
            check(panel.directoryURL?.standardizedFileURL == outDir.standardizedFileURL,
                  "save sheet suggests the last export's folder (got \(panel.directoryURL?.path ?? "nil"))")
            // -[NSSavePanel ok:] raises "not implemented" on macOS 27 and the panel's content is an
            // NSRemoteView from the open-and-save service, so Save is pressed with a Return key.
            // -[NSSavePanel ok:] raises "not implemented" on macOS 27, the panel's content is an
            // NSRemoteView from the open-and-save service, and a synthetic Return goes nowhere while
            // the app is not active. The accessibility tree bridges the remote view, so press Save there.
            // the remote view's contents are not bridged for the process itself (the sheet shows one
            // roleless child), so System Events presses it from outside.
            check(pressSaveFromOutside(), "System Events pressed Save in the save sheet")
        }
        await wait("save sheet export", timeout: 30) { m.busyMessage == nil && window.attachedSheet == nil }
        try? await Task.sleep(for: .milliseconds(300))
        check(FileManager.default.fileExists(atPath: small.path), "Save in the save sheet writes \(small.lastPathComponent)")
        check(!m.isDirty, "save sheet export clears the edited state")

        // Export… chosen in the close alert: the window closes by itself once the export lands
        m.closeAfterExport = true
        await m.export(to: url, options: m.defaultExportOptions())
        try? await Task.sleep(for: .milliseconds(300))
        check(AppDelegate.shared?.editorControllers.isEmpty == true, "window closed after the export requested from the close alert")

        finish()
    }
}
