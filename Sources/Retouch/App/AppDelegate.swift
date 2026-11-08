import AppKit
import RetouchCore
import SwiftUI

/// Opens files (Finder, Open panel, drag and drop, Open Recent), owns the editor windows,
/// and asks before quitting with unexported changes.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate? { NSApp.delegate as? AppDelegate }

    private var editors: [EditorWindowController] = []
    /// Open editor windows, oldest first (used by the self-test).
    var editorControllers: [EditorWindowController] { editors }
    /// The editor frame with no image in it, shown at launch and again when the last image closes.
    private var emptyWindow: NSWindow?
    private var quitting = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The first NSDocumentController created becomes the shared one; ours routes Open Recent here.
        _ = RecentDocumentsController()
        NSApp.mainMenu = MainMenu.make()
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SelfTest.runIfRequested() { return }
        // Files opened from Finder at launch have arrived by now; with none, open the empty workspace.
        if editors.isEmpty { showEmptyWindow() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        open(urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showEmptyWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let dirty = editors.filter { $0.model.hasUnexportedWork }
        guard !dirty.isEmpty else {
            quitting = true
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = dirty.count == 1
            ? "“\(dirty[0].model.fileURL.lastPathComponent)” has changes you haven't exported."
            : "\(dirty.count) images have changes you haven't exported."
        alert.informativeText = "If you quit now, those changes are lost."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit Anyway")
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        quitting = true
        return .terminateNow
    }

    // MARK: - Opening

    func open(_ urls: [URL]) {
        for url in urls { open(url) }
    }

    func open(_ url: URL) {
        let url = url.standardizedFileURL
        if let existing = editors.first(where: { $0.model.fileURL == url }) {
            existing.showWindow(nil)
            return
        }
        let controller = EditorWindowController(url: url) { [weak self] closed in
            guard let self else { return }
            editors.removeAll { $0 === closed }
            // Closing the last image leaves the workspace, not nothing (Photoshop's empty frame).
            if editors.isEmpty && !quitting { showEmptyWindow() }
        }
        if let front = editors.last?.window, let window = controller.window {
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: front.frame.minX, y: front.frame.maxY)))
        } else if let empty = emptyWindow, empty.isVisible, let window = controller.window {
            window.setFrame(empty.frame, display: false) // the image takes the workspace's place
        }
        editors.append(controller)
        controller.showWindow(nil)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        emptyWindow?.orderOut(nil)
    }

    @objc func openImage(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ImageFiles.openableTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in self?.open(urls) }
        }
    }

    private func showEmptyWindow() {
        if let emptyWindow {
            emptyWindow.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1320, height: 860),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Retouch"
        window.minSize = NSSize(width: 820, height: 520)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed // images open as their own window, never as a tab of this one
        window.contentView = NSHostingView(rootView: EmptyEditorView(
            onOpen: { [weak self] in self?.openImage(nil) },
            onDrop: { [weak self] urls in self?.open(urls) }))
        window.center()
        window.makeKeyAndOrderFront(nil)
        emptyWindow = window
    }
}
