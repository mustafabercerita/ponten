import AppKit
import SwiftUI

/// Hosts `MenuBarView` in-process for CI where cross-process Accessibility is unavailable.
/// Must be created on the main thread.
final class E2EInProcessHost {
    let dataDirectory: String
    let manager: SignatureManager
    private let window: NSWindow

    init(dataDirectory: String) {
        self.dataDirectory = dataDirectory
        let store = SignatureStore(storageDirectory: URL(fileURLWithPath: dataDirectory, isDirectory: true))
        self.manager = SignatureManager(store: store)

        let contentView = MenuBarView()
            .environmentObject(manager)
        let hostingController = NSHostingController(rootView: contentView)

        let hasSignature = manager.signatureImage != nil
        let height = max(hasSignature ? 360 : 260, 400)
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 300, height: height)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Ponten Menu"
        window.identifier = NSUserInterfaceItemIdentifier("PontenMenu")
        window.setAccessibilityIdentifier("PontenMenu")
        window.contentViewController = hostingController
        window.center()
        window.makeKeyAndOrderFront(nil)
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