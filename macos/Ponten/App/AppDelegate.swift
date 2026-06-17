import AppKit
import SwiftUI

/// AppDelegate — manages the NSStatusItem (menu bar icon) and its popover.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var signatureManager = SignatureManager.shared
    private var eventMonitor: EventMonitor?
    private var globalHotkeyMonitor: Any?
    private var e2eWindow: NSWindow?

    private var observers: [NSObjectProtocol] = []

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        if E2EMode.isEnabled {
            NSApp.setActivationPolicy(.regular)
            setupE2EWindow()
            return
        }

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
            self?.checkForUpdates(silent: false)
        }
        
        observers.append(closeObs)
        observers.append(updateObs)
        
        // Auto-check for updates silently on launch
        checkForUpdates(silent: true)
        
        // Check every 12 hours
        Timer.scheduledTimer(withTimeInterval: 12 * 3600, repeats: true) { [weak self] _ in
            self?.checkForUpdates(silent: true)
        }
    }

    func checkForUpdates(silent: Bool = false) {
        // Native GitHub Releases API check
        guard let url = URL(string: "https://api.github.com/repos/mustafabercerita/ponten/releases/latest") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Ponten-MacApp", forHTTPHeaderField: "User-Agent")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tagName = json["tag_name"] as? String {
                    
                    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                    
                    let cleanTag = tagName.replacingOccurrences(of: "v", with: "")
                    let cleanCurrent = currentVersion.replacingOccurrences(of: "v", with: "")
                    
                    if cleanTag.compare(cleanCurrent, options: .numeric) == .orderedDescending {
                        guard let assets = json["assets"] as? [[String: Any]],
                              let dmgAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
                              let downloadUrlString = dmgAsset["browser_download_url"] as? String,
                              let downloadUrl = URL(string: downloadUrlString) else {
                            if !silent { self?.signatureManager.showToast("Update found, but no DMG available.") }
                            return
                        }
                        
                        if silent {
                            self?.signatureManager.showToast("Update v\(cleanTag) available. Use Check for Updates to install.")
                        } else {
                            self?.promptForUpdateDownload(version: cleanTag, downloadURL: downloadUrl)
                        }
                        
                    } else {
                        if !silent { self?.signatureManager.showToast("You're up to date! (v\(currentVersion))") }
                    }
                } else {
                    if !silent { self?.signatureManager.showToast("Update check failed. Check network.") }
                }
            }
        }
        task.resume()
    }

    private func promptForUpdateDownload(version: String, downloadURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Ponten v\(version) is available. Download and install now?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        signatureManager.showToast("Downloading Update v\(version)...")
        downloadAndInstallUpdate(from: downloadURL)
    }
    
    private func downloadAndInstallUpdate(from url: URL) {
        let task = URLSession.shared.downloadTask(with: url) { [weak self] localURL, response, error in
            guard let localURL = localURL, error == nil else {
                DispatchQueue.main.async {
                    self?.signatureManager.showToast("Failed to download update.")
                }
                return
            }
            
            let fm = FileManager.default
            let secureTempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            
            do {
                try fm.createDirectory(at: secureTempDir, withIntermediateDirectories: true)
                let dmgDestination = secureTempDir.appendingPathComponent("Ponten_Update.dmg")
                let scriptDestination = secureTempDir.appendingPathComponent("install_update.sh")
                
                if fm.fileExists(atPath: dmgDestination.path) {
                    try fm.removeItem(at: dmgDestination)
                }
                try fm.moveItem(at: localURL, to: dmgDestination)
                
                // Build the bash script
                let scriptContent = """
                #!/bin/bash
                
                # Wait for the app to terminate
                while pgrep -x "Ponten" > /dev/null; do
                    sleep 1
                done
                
                # Detach any existing stuck mounts
                hdiutil detach "/Volumes/PontenUpdate" -force 2>/dev/null || true
                
                # Mount the DMG
                hdiutil attach "\(dmgDestination.path)" -mountpoint "/Volumes/PontenUpdate" -nobrowse
                
                # Copy the app to Applications (replacing the old one)
                rm -rf "/Applications/Ponten.app"
                cp -R "/Volumes/PontenUpdate/Ponten.app" "/Applications/"
                
                # Unmount the DMG
                hdiutil detach "/Volumes/PontenUpdate" -force
                
                # Clean up the secure temp dir
                rm -rf "\(secureTempDir.path)"
                
                # Open the new app
                open -a "/Applications/Ponten.app"
                """
                
                try scriptContent.write(to: scriptDestination, atomically: true, encoding: .utf8)
                
                // Make the script executable
                var attributes = [FileAttributeKey: Any]()
                attributes[.posixPermissions] = NSNumber(value: 0o755)
                try fm.setAttributes(attributes, ofItemAtPath: scriptDestination.path)
                
                DispatchQueue.main.async {
                    self?.signatureManager.showToast("Update downloaded! Restarting...")
                    
                    // Give the toast 1.5 seconds to show, then execute and quit
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: "/bin/bash")
                        process.arguments = [scriptDestination.path]
                        
                        do {
                            try process.run()
                            NSApp.terminate(nil)
                        } catch {
                            print("Failed to run update script: \\(error)")
                        }
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    self?.signatureManager.showToast("Error installing update.")
                    print("Install error: \\(error)")
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

    // MARK: - E2E Window

    private func setupE2EWindow() {
        NSApp.setActivationPolicy(.regular)

        let contentView = MenuBarView()
            .environmentObject(signatureManager)
        let hostingController = NSHostingController(rootView: contentView)

        let hasSignature = signatureManager.signatureImage != nil
        let height = max(hasSignature ? 360 : 260, 400)
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 300, height: height)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Ponten Menu"
        window.contentViewController = hostingController
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        e2eWindow = window
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
            button.toolTip = "Ponten"
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

        let hasSignature = signatureManager.signatureImage != nil
        let height: CGFloat = hasSignature ? 360 : 260
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 300, height: height)
        popover.contentViewController = hostingController
        popover.contentSize = NSSize(width: 300, height: height)
    }

    // MARK: - Event Monitor (close on outside click)

    private func setupEventMonitor() {
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.popover.isShown, !self.signatureManager.isFileDialogOpen else { return }
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
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Quit Ponten", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            if let button = statusItem.button {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
            }
            return
        }

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
