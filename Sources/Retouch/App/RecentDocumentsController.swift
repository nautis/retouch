import AppKit

/// Retouch has no NSDocument classes, so File > Open Recent is routed to the app delegate.
final class RecentDocumentsController: NSDocumentController {
    override func openDocument(withContentsOf url: URL, display displayDocument: Bool,
                               completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void) {
        AppDelegate.shared?.open(url)
        completionHandler(nil, false, nil)
    }
}
