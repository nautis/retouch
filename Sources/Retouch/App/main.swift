import AppKit

SelfTest.runHelperIfRequested() // `--ax-press`: a self-test helper that exits before the app starts
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
