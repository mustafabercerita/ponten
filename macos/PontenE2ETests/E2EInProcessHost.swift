import AppKit

/// Hosts an AppKit menu panel in-process for CI where cross-process Accessibility is unavailable.
/// Must be created on the main thread while the run loop is being pumped.
final class E2EInProcessHost {
    let dataDirectory: String
    let manager: SignatureManager
    private let window: NSWindow
    private let panelView: E2EMenuPanelView

    init(dataDirectory: String) {
        self.dataDirectory = dataDirectory
        let store = SignatureStore(storageDirectory: URL(fileURLWithPath: dataDirectory, isDirectory: true))
        self.manager = SignatureManager(store: store)

        let hasSignature = !manager.signatures.isEmpty
        let height = max(hasSignature ? 360 : 260, 400)
        let frame = NSRect(x: 0, y: 0, width: 300, height: CGFloat(height))

        let panelView = E2EMenuPanelView(manager: manager, frame: frame)
        self.panelView = panelView

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Ponten Menu"
        window.identifier = NSUserInterfaceItemIdentifier("PontenMenu")
        window.setAccessibilityIdentifier("PontenMenu")
        window.contentView = panelView
        window.isReleasedWhenClosed = true
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        panelView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        NSAccessibility.post(element: window, notification: .created)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    var rootElement: AXUIElement {
        AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
    }

    func close() {
        window.close()
    }
}