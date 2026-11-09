import AppKit

/// The menu bar. Shortcuts follow Photoshop where it has one (Auto Tone ⇧⌘L, Hue/Saturation ⌘U,
/// Image Size ⌥⌘I, Export As ⌥⇧⌘W, Deselect ⌘D, Fit on Screen ⌘0, 100% ⌘1).
/// Actions go to the front editor window's controller through the responder chain.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(imageMenu()))
        main.addItem(submenu(filterMenu()))
        main.addItem(submenu(selectMenu()))
        main.addItem(submenu(viewMenu()))
        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = key.isEmpty ? [] : mods
        return i
    }

    private static func appMenu() -> NSMenu {
        let m = NSMenu(title: "Retouch")
        m.addItem(item("About Retouch", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        m.addItem(.separator())
        m.addItem(item("Hide Retouch", #selector(NSApplication.hide(_:)), "h"))
        m.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        m.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        m.addItem(.separator())
        m.addItem(item("Quit Retouch", #selector(NSApplication.terminate(_:)), "q"))
        return m
    }

    private static func fileMenu() -> NSMenu {
        let m = NSMenu(title: "File")
        m.addItem(item("Open…", #selector(AppDelegate.openImage(_:)), "o"))
        let recent = NSMenu(title: "Open Recent")
        recent.addItem(item("Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:))))
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recent
        m.addItem(recentItem)
        m.addItem(.separator())
        m.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        m.addItem(item("Save", #selector(EditorWindowController.saveImage(_:)), "s"))
        m.addItem(item("Export As…", #selector(EditorWindowController.exportImage(_:)), "w", [.command, .option, .shift]))
        m.addItem(item("Show Exported File in Finder", #selector(EditorWindowController.revealExport(_:)), "r", [.command, .shift]))
        return m
    }

    private static func editMenu() -> NSMenu {
        let m = NSMenu(title: "Edit")
        m.addItem(item("Undo", #selector(EditorWindowController.undoEdit(_:)), "z"))
        m.addItem(item("Redo", #selector(EditorWindowController.redoEdit(_:)), "z", [.command, .shift]))
        m.addItem(.separator())
        // Standard text editing, for the number fields in dialogs.
        m.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        m.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        m.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        return m
    }

    private static func imageMenu() -> NSMenu {
        let m = NSMenu(title: "Image")
        m.addItem(item("Auto Tone", #selector(EditorWindowController.autoTone(_:)), "l", [.command, .shift]))
        m.addItem(item("Auto Contrast", #selector(EditorWindowController.autoContrast(_:)), "l", [.command, .option, .shift]))
        m.addItem(item("Auto Color", #selector(EditorWindowController.autoColor(_:)), "b", [.command, .shift]))
        m.addItem(.separator())
        m.addItem(item("Hue/Saturation…", #selector(EditorWindowController.hueSaturation(_:)), "u"))
        m.addItem(.separator())
        m.addItem(item("Image Size…", #selector(EditorWindowController.imageSize(_:)), "i", [.command, .option]))
        m.addItem(item("Crop to Selection", #selector(EditorWindowController.cropToSelection(_:))))
        let rotation = NSMenu(title: "Image Rotation")
        rotation.addItem(item("180°", #selector(EditorWindowController.rotate180(_:))))
        rotation.addItem(item("90° Clockwise", #selector(EditorWindowController.rotate90CW(_:))))
        rotation.addItem(item("90° Counter Clockwise", #selector(EditorWindowController.rotate90CCW(_:))))
        rotation.addItem(item("Arbitrary…", #selector(EditorWindowController.rotateArbitrary(_:))))
        m.addItem(submenu(rotation))
        return m
    }

    private static func filterMenu() -> NSMenu {
        let m = NSMenu(title: "Filter")
        let sharpen = NSMenu(title: "Sharpen")
        sharpen.addItem(item("Sharpen", #selector(EditorWindowController.sharpen(_:))))
        sharpen.addItem(item("Unsharp Mask…", #selector(EditorWindowController.unsharpMask(_:))))
        m.addItem(submenu(sharpen))
        let pixelate = NSMenu(title: "Pixelate")
        pixelate.addItem(item("Crystallize…", #selector(EditorWindowController.crystallize(_:))))
        pixelate.addItem(item("Mosaic…", #selector(EditorWindowController.mosaic(_:))))
        pixelate.addItem(item("Pointillize…", #selector(EditorWindowController.pointillize(_:))))
        m.addItem(submenu(pixelate))
        return m
    }

    private static func selectMenu() -> NSMenu {
        let m = NSMenu(title: "Select")
        m.addItem(item("All", #selector(NSResponder.selectAll(_:)), "a"))
        m.addItem(item("Deselect", #selector(EditorWindowController.deselectPixels(_:)), "d"))
        return m
    }

    private static func viewMenu() -> NSMenu {
        let m = NSMenu(title: "View")
        m.addItem(item("Zoom In", #selector(EditorWindowController.zoomIn(_:)), "="))
        m.addItem(item("Zoom Out", #selector(EditorWindowController.zoomOut(_:)), "-"))
        m.addItem(item("Fit on Screen", #selector(EditorWindowController.zoomToFit(_:)), "0"))
        m.addItem(item("100%", #selector(EditorWindowController.zoomActual(_:)), "1"))
        m.addItem(.separator())
        m.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return m
    }

    private static func windowMenu() -> NSMenu {
        let m = NSMenu(title: "Window")
        m.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        m.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        m.addItem(.separator())
        m.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return m
    }
}
