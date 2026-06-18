import AppKit
import Combine
import SwiftUI

/// AppDelegate — manages the NSStatusItem (menu bar icon) and its popover.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var signatureManager = SignatureManager.shared
    private var eventMonitor: EventMonitor?
    private var e2eWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    private var observers: [NSObjectProtocol] = []

    // MARK: - App Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        if E2EMode.isEnabled {
            NSApp.setActivationPolicy(.regular)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if E2EMode.isEnabled {
            setupE2EWindow()
            return
        }

        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupPopover()
        setupEventMonitor()
        setupGlobalHotkey()
        setupToastPresentation()
        setupPopoverObservers()

        let closeObs = NotificationCenter.default.addObserver(forName: NSNotification.Name("ClosePopover"), object: nil, queue: .main) { [weak self] _ in
            self?.closePopover()
        }

        let updateObs = NotificationCenter.default.addObserver(forName: NSNotification.Name("CheckForUpdates"), object: nil, queue: .main) { [weak self] _ in
            self?.checkForUpdates(silent: false)
        }

        observers.append(closeObs)
        observers.append(updateObs)

        checkForUpdates(silent: true)

        Timer.scheduledTimer(withTimeInterval: 12 * 3600, repeats: true) { [weak self] _ in
            self?.checkForUpdates(silent: true)
        }
    }

    func checkForUpdates(silent: Bool = false) {
        guard let url = URL(string: "https://api.github.com/repos/mustafabercerita/ponten/releases/latest") else { return }

        var request = URLRequest(url: url)
        request.setValue("Ponten-MacApp", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error {
                    if !silent { self?.signatureManager.showToast("Update check failed: \(error.localizedDescription)") }
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    if !silent { self?.signatureManager.showToast("Update check failed. Check network.") }
                    return
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    if !silent {
                        let message: String
                        switch httpResponse.statusCode {
                        case 403:
                            message = "Update check blocked (rate limit). Try again later."
                        case 429:
                            message = "Too many update checks. Try again later."
                        default:
                            message = "Update check failed (HTTP \(httpResponse.statusCode))."
                        }
                        self?.signatureManager.showToast(message)
                    }
                    return
                }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    if !silent { self?.signatureManager.showToast("Update check failed. Check network.") }
                    return
                }

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
        downloadAndInstallUpdate(from: downloadURL, version: version)
    }

    private func downloadAndInstallUpdate(from url: URL, version: String) {
        let task = URLSession.shared.downloadTask(with: url) { [weak self] localURL, response, error in
            guard let self else { return }

            DispatchQueue.main.async {
                if let error {
                    self.signatureManager.showToast("Failed to download update: \(error.localizedDescription)")
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    self.signatureManager.showToast("Failed to download update (HTTP \(statusCode)).")
                    return
                }

                guard let localURL else {
                    self.signatureManager.showToast("Failed to download update.")
                    return
                }

                if self.isAppSandboxed() {
                    self.finishManualUpdateInstall(localURL: localURL, version: version)
                    return
                }

                self.runAutomatedUpdateInstall(localURL: localURL, version: version)
            }
        }
        task.resume()
    }

    private func runAutomatedUpdateInstall(localURL: URL, version: String) {
        let fm = FileManager.default
        let secureTempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let mountPoint = "/Volumes/PontenUpdate-\(UUID().uuidString)"

        do {
            try fm.createDirectory(at: secureTempDir, withIntermediateDirectories: true)
            let dmgDestination = secureTempDir.appendingPathComponent("Ponten_Update.dmg")
            let scriptDestination = secureTempDir.appendingPathComponent("install_update.sh")

            if fm.fileExists(atPath: dmgDestination.path) {
                try fm.removeItem(at: dmgDestination)
            }
            try fm.moveItem(at: localURL, to: dmgDestination)

            let scriptContent = """
            #!/bin/bash

            while pgrep -x "Ponten" > /dev/null; do
                sleep 1
            done

            hdiutil detach "\(mountPoint)" -force 2>/dev/null || true

            if ! hdiutil attach "\(dmgDestination.path)" -mountpoint "\(mountPoint)" -nobrowse; then
                exit 1
            fi

            if [ ! -d "\(mountPoint)/Ponten.app" ]; then
                hdiutil detach "\(mountPoint)" -force
                exit 1
            fi

            rm -rf "/Applications/Ponten.app"
            cp -R "\(mountPoint)/Ponten.app" "/Applications/"

            hdiutil detach "\(mountPoint)" -force
            rm -rf "\(secureTempDir.path)"
            open -a "/Applications/Ponten.app"
            """

            try scriptContent.write(to: scriptDestination, atomically: true, encoding: .utf8)

            var attributes = [FileAttributeKey: Any]()
            attributes[.posixPermissions] = NSNumber(value: 0o755)
            try fm.setAttributes(attributes, ofItemAtPath: scriptDestination.path)

            signatureManager.showToast("Update downloaded! Restarting...")

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [scriptDestination.path]

                do {
                    try process.run()
                    NSApp.terminate(nil)
                } catch {
                    self?.finishManualUpdateInstall(localURL: dmgDestination, version: version)
                }
            }
        } catch {
            finishManualUpdateInstall(localURL: localURL, version: version)
        }
    }

    private func finishManualUpdateInstall(localURL: URL, version: String) {
        let fm = FileManager.default
        let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let destination = downloads.appendingPathComponent("Ponten-\(version).dmg")

        do {
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: localURL, to: destination)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
            signatureManager.showToast("Update saved to Downloads. Open the DMG to install manually.")
        } catch {
            signatureManager.showToast("Update downloaded but could not be saved. Download the DMG from GitHub manually.")
        }
    }

    private func isAppSandboxed() -> Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        teardownGlobalHotkey()
        MenuBarToastPresenter.shared.hide()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    // MARK: - E2E Window

    private func setupE2EWindow() {
        let contentView = MenuBarView()
            .environmentObject(signatureManager)
        let hostingController = NSHostingController(rootView: contentView)

        let height = preferredPopoverHeight()
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
        NSApp.activate(ignoringOtherApps: true)
        e2eWindow = window
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
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

        let height = preferredPopoverHeight()
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 300, height: height)
        popover.contentViewController = hostingController
        popover.contentSize = NSSize(width: 300, height: height)
    }

    private func setupPopoverObservers() {
        signatureManager.$signatures
            .map(\.count)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopoverSize()
            }
            .store(in: &cancellables)
    }

    private func preferredPopoverHeight() -> CGFloat {
        signatureManager.signatures.isEmpty ? 260 : 360
    }

    private func updatePopoverSize() {
        let height = preferredPopoverHeight()
        popover?.contentSize = NSSize(width: 300, height: height)
        popover?.contentViewController?.view.frame = NSRect(x: 0, y: 0, width: 300, height: height)
    }

    // MARK: - Event Monitor (close on outside click)

    private func setupEventMonitor() {
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.popover.isShown, !self.signatureManager.isModalPresented else { return }
            if let event, self.isEventInsidePopover(event) { return }
            self.closePopover()
        }
    }

    private func isEventInsidePopover(_ event: NSEvent) -> Bool {
        guard let popoverWindow = popover.contentViewController?.view.window else { return false }
        if event.window === popoverWindow { return true }
        return popoverWindow.frame.contains(NSEvent.mouseLocation)
    }

    // MARK: - Global Hotkey (⌥⌘S)

    private func setupGlobalHotkey() {
        GlobalShortcutManager.shared.onRegistrationFailure = { [weak self] message in
            self?.signatureManager.showToast(message)
        }

        GlobalShortcutManager.shared.action = { [weak self] in
            let copied = self?.signatureManager.copySignatureToClipboard() ?? false
            if !copied && self?.signatureManager.signatureImage == nil {
                self?.openPopover()
            }
        }
    }

    private func setupToastPresentation() {
        signatureManager.onToastOutsidePopover = { [weak self] message in
            guard let self, !self.popover.isShown else { return }
            MenuBarToastPresenter.shared.show(message: message, statusItem: self.statusItem, duration: self.signatureManager.toastDuration)
        }
    }

    private func teardownGlobalHotkey() {
        GlobalShortcutManager.shared.unregister()
    }

    // MARK: - Popover Control

    @objc private func togglePopover(_ sender: Any?) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            let menu = NSMenu()

            let addItem = NSMenuItem(title: "Add Signature...", action: #selector(addSignatureFromMenu), keyEquivalent: "")
            addItem.target = self
            menu.addItem(addItem)

            let drawItem = NSMenuItem(title: "Draw Signature...", action: #selector(drawSignatureFromMenu), keyEquivalent: "")
            drawItem.target = self
            menu.addItem(drawItem)

            menu.addItem(.separator())

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

        updatePopoverSize()
        MenuBarToastPresenter.shared.hide()
        MenuBarToastPresenter.shared.restoreToolTip(on: statusItem)

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        eventMonitor?.start()
    }

    func closePopover() {
        guard !signatureManager.isModalPresented else { return }
        popover.performClose(nil)
        eventMonitor?.stop()
    }

    @objc private func addSignatureFromMenu() {
        openPopover()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.signatureManager.openFilePicker()
        }
    }

    @objc private func drawSignatureFromMenu() {
        openPopover()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.signatureManager.isDrawingSheetOpen = true
        }
    }
}