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
                        
                        self?.signatureManager.showToast("Downloading Update v\(cleanTag)...")
                        self?.downloadAndInstallUpdate(from: downloadUrl)
                        
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
    
    private func downloadAndInstallUpdate(from url: URL) {
        let task = URLSession.shared.downloadTask(with: url) { [weak self] localURL, response, error in
            guard let localURL = localURL, error == nil else {
                DispatchQueue.main.async {
                    self?.signatureManager.showToast("Failed to download update.")
                }
                return
            }
            
            let fm = FileManager.default
            let dmgDestination = URL(fileURLWithPath: "/tmp/Ponten_Update.dmg")
            let scriptDestination = URL(fileURLWithPath: "/tmp/install_update.sh")
            
            do {
                if fm.fileExists(atPath: dmgDestination.path) {
                    try fm.removeItem(at: dmgDestination)
                }
                try fm.moveItem(at: localURL, to: dmgDestination)
                
                // Build the bash script
                let scriptContent = """
                #!/bin/bash
                # Wait for the app to terminate
                sleep 2
                
                # Mount the DMG
                hdiutil attach "/tmp/Ponten_Update.dmg" -mountpoint "/Volumes/PontenUpdate" -nobrowse
                
                # Copy the app to Applications (replacing the old one)
                rm -rf "/Applications/Ponten.app"
                cp -R "/Volumes/PontenUpdate/Ponten.app" "/Applications/"
                
                # Unmount the DMG
                hdiutil detach "/Volumes/PontenUpdate" -force
                
                # Clean up the DMG
                rm -f "/tmp/Ponten_Update.dmg"
                
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
