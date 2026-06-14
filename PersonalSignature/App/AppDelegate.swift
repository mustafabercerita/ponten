import AppKit
import SwiftUI

/// AppDelegate — manages the NSStatusItem (menu bar icon) and its popover.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var signatureManager = SignatureManager.shared
    private var eventMonitor: EventMonitor?
    private var globalHotkeyMonitor: Any?

    private var observers: [NSObjectProtocol] = []

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only: hide from Dock and ⌘Tab switcher
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupPopover()
        setupEventMonitor()
        setupGlobalHotkey()
        
        let closeObs = NotificationCenter.default.addObserver(forName: NSNotification.Name("ClosePopover"), object: nil, queue: .main) { [weak self] _ in
            self?.closePopover()
        }
        
        let updateObs = NotificationCenter.default.addObserver(forName: NSNotification.Name("CheckForUpdates"), object: nil, queue: .main) { [weak self] _ in
            self?.checkForUpdates()
        }
        
        observers.append(closeObs)
        observers.append(updateObs)
    }

    func checkForUpdates() {
        // Native GitHub Releases API check
        guard let url = URL(string: "https://api.github.com/repos/mustafabercerita/personal-signature/releases/latest") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("PersonalSignature-MacApp", forHTTPHeaderField: "User-Agent")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tagName = json["tag_name"] as? String {
                    
                    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                    
                    let cleanTag = tagName.replacingOccurrences(of: "v", with: "")
                    let cleanCurrent = currentVersion.replacingOccurrences(of: "v", with: "")
                    
                    if cleanTag.compare(cleanCurrent, options: .numeric) == .orderedDescending {
                        self?.signatureManager.showToast("Update Available (v\(cleanTag))! Opening browser...")
                        if let htmlUrl = json["html_url"] as? String, let updateUrl = URL(string: htmlUrl) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                NSWorkspace.shared.open(updateUrl)
                            }
                        }
                    } else {
                        self?.signatureManager.showToast("You're up to date! (v\(currentVersion))")
                    }
                } else {
                    self?.signatureManager.showToast("Update check failed. Check network.")
                }
            }
        }
        task.resume()
    }

    func applicationWillTerminate(_ notification: Notification) {
        teardownGlobalHotkey()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            // macOS automatically treats images ending with "Template" as template images
            // (meaning it will color them black/white automatically based on Light/Dark mode).
            let image = NSImage(named: "MenuBarIconTemplate")
            image?.isTemplate = true
            button.image = image
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Personal Signature"
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = true

        let contentView = MenuBarView()
            .environmentObject(signatureManager)
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 300, height: 380)
        popover.contentViewController = hostingController
        popover.contentSize = NSSize(width: 300, height: 380)
    }

    // MARK: - Event Monitor (close on outside click)

    private func setupEventMonitor() {
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.closePopover()
        }
    }

    // MARK: - Global Hotkey (⌥⌘S)

    private func setupGlobalHotkey() {
        GlobalShortcutManager.shared.action = { [weak self] in
            let copied = self?.signatureManager.copySignatureToClipboard() ?? false
            if !copied && self?.signatureManager.signatureImage == nil {
                // No signature yet — open popover to let user add one
                self?.openPopover()
            }
        }
    }

    private func teardownGlobalHotkey() {
        // Handled automatically by system on app exit, or could add an unregister method
    }

    // MARK: - Popover Control

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover()
        } else {
            openPopover()
        }
    }

    func openPopover() {
        guard let button = statusItem.button else { return }

        // Resize based on current state
        let hasSignature = signatureManager.signatureImage != nil
        let height: CGFloat = hasSignature ? 360 : 260
        popover.contentSize = NSSize(width: 300, height: height)

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        eventMonitor?.start()
    }

    func closePopover() {
        popover.performClose(nil)
        eventMonitor?.stop()
    }
}
