import AppKit
import ApplicationServices
import XCTest

/// Shared harness for driving Ponten UI via Accessibility APIs.
/// Uses in-process hosting on CI where cross-process AX is unavailable.
/// Category: E2E — tests using this fixture must run serially (one Ponten instance at a time).
final class E2ETestFixture {

    private static let serializationLock = NSLock()

    /// In-process hosting is default (same-process AX). Opt out with `PONTEN_E2E_OUT_OF_PROCESS=1`.
    static var useInProcess: Bool {
        ProcessInfo.processInfo.environment["PONTEN_E2E_OUT_OF_PROCESS"] != "1"
    }

    let dataDirectory: String
    private let deleteDataDirectoryOnDispose: Bool
    private let usesInProcess: Bool
    private var inProcessHost: E2EInProcessHost?
    private(set) var process: Process?
    private(set) var appPID: pid_t = 0

    var isAppRunning: Bool {
        guard appPID != 0, let running = NSRunningApplication(processIdentifier: appPID) else {
            return false
        }
        return !running.isTerminated
    }

    init(dataDirectory: String? = nil) throws {
        deleteDataDirectoryOnDispose = dataDirectory == nil
        let resolvedDirectory = dataDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("PontenE2E_\(UUID().uuidString)", isDirectory: true)
            .path
        self.dataDirectory = resolvedDirectory

        try FileManager.default.createDirectory(
            atPath: resolvedDirectory,
            withIntermediateDirectories: true
        )

        usesInProcess = Self.useInProcess
        try Self.withSerialization {
            if usesInProcess {
                try launchInProcess(dataDirectory: resolvedDirectory)
            } else {
                Self.killStalePontenProcesses()
                try launchApp(dataDirectory: resolvedDirectory)
            }
        }
    }

    deinit {
        try? Self.withSerialization {
            terminateApp()
        }
        if deleteDataDirectoryOnDispose {
            try? FileManager.default.removeItem(atPath: dataDirectory)
        }
    }

    // MARK: - App lifecycle

    private static func killStalePontenProcesses() {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.localizedName == "Ponten" || $0.bundleURL?.lastPathComponent == "Ponten.app"
        }
        for app in running {
            app.forceTerminate()
            _ = app.waitUntilTerminated(timeout: 3)
        }
    }

    static func resolveAppBundle() throws -> URL {
        let configuration = ProcessInfo.processInfo.environment["CONFIGURATION"] ?? "Debug"
        let testBundle = Bundle(for: E2ETestFixture.self).bundleURL

        var candidates: [URL] = []

        if let builtProducts = ProcessInfo.processInfo.environment["BUILT_PRODUCTS_DIR"] {
            candidates.append(URL(fileURLWithPath: builtProducts, isDirectory: true).appendingPathComponent("Ponten.app"))
        }

        candidates.append(contentsOf: [
            testBundle.deletingLastPathComponent().appendingPathComponent("Ponten.app"),
            testBundle.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Ponten.app"),
            URL(fileURLWithPath: "build/\(configuration)/Ponten.app", relativeTo: testBundle.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()),
            URL(fileURLWithPath: ".build/\(configuration.lowercased())/Ponten.app", relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)),
            URL(fileURLWithPath: "macos/.build/\(configuration.lowercased())/Ponten.app", relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)),
        ])

        let projectRoot = testBundle
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        candidates.append(projectRoot.appendingPathComponent(".build/debug/Ponten.app"))
        candidates.append(projectRoot.appendingPathComponent("macos/.build/debug/Ponten.app"))

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        if let derivedDataMatch = try? findAppInDerivedData() {
            return derivedDataMatch
        }

        throw NSError(
            domain: "PontenE2E",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Ponten.app not found. Build the Ponten target before running E2E tests."]
        )
    }

    private static func findAppInDerivedData() throws -> URL? {
        let derivedDataRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: derivedDataRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let pontenProjects = entries.filter { $0.lastPathComponent.hasPrefix("Ponten-") }
        let sorted = pontenProjects.sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhs > rhs
        }

        for projectDir in sorted {
            let products = projectDir
                .appendingPathComponent("Build/Products", isDirectory: true)
            guard let configs = try? FileManager.default.contentsOfDirectory(at: products, includingPropertiesForKeys: nil) else {
                continue
            }
            for config in configs {
                let app = config.appendingPathComponent("Ponten.app")
                if FileManager.default.fileExists(atPath: app.path) {
                    return app
                }
            }
        }

        return nil
    }

    private func launchInProcess(dataDirectory: String) throws {
        setenv("PONTEN_E2E", "1", 1)
        setenv("PONTEN_DATA_DIR", dataDirectory, 1)
        setenv("PONTEN_E2E_IN_PROCESS", "1", 1)

        try performOnMainWithRunLoop {
            Self.ensureTestApplication()
            self.inProcessHost = E2EInProcessHost(dataDirectory: dataDirectory)
            self.appPID = ProcessInfo.processInfo.processIdentifier
        }

        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if waitForMainWindow(timeout: 0.25) != nil {
                return
            }
            pumpMainRunLoop(for: 0.1)
        }

        throw NSError(
            domain: "PontenE2E",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "In-process Ponten window was not found."]
        )
    }

    private static var applicationBootstrapped = false

    private static func ensureTestApplication() {
        let app = NSApplication.shared
        if !applicationBootstrapped {
            app.setActivationPolicy(.regular)
            app.finishLaunching()
            applicationBootstrapped = true
        }
        app.activate(ignoringOtherApps: true)
    }

    private func launchApp(dataDirectory: String) throws {
        let appBundle = try Self.resolveAppBundle()
        let executable = appBundle.appendingPathComponent("Contents/MacOS/Ponten")

        var environment = ProcessInfo.processInfo.environment
        environment["PONTEN_E2E"] = "1"
        environment["PONTEN_DATA_DIR"] = dataDirectory

        let appProcess = Process()
        appProcess.executableURL = executable
        appProcess.arguments = ["--e2e", "--data-dir=\(dataDirectory)"]
        appProcess.environment = environment
        try appProcess.run()

        process = appProcess
        appPID = appProcess.processIdentifier

        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if !appProcess.isRunning {
                throw NSError(
                    domain: "PontenE2E",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Ponten exited before the E2E window appeared (status \(appProcess.terminationStatus))."]
                )
            }
            if waitForMainWindow(timeout: 0.5) != nil {
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }

        throw NSError(
            domain: "PontenE2E",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Ponten main window was not found within 20 seconds."]
        )
    }

    private func terminateApp() {
        if usesInProcess {
            try? performOnMainWithRunLoop {
                self.inProcessHost?.close()
                self.inProcessHost = nil
            }
        } else if appPID != 0,
                  let running = NSRunningApplication(processIdentifier: appPID),
                  !running.isTerminated {
            running.terminate()
            _ = running.waitUntilTerminated(timeout: 5)
            if !running.isTerminated {
                running.forceTerminate()
                _ = running.waitUntilTerminated(timeout: 3)
            }
            Self.killStalePontenProcesses()
        }

        process = nil
        appPID = 0
    }

    // MARK: - Accessibility helpers

    func waitForMainWindow(timeout: TimeInterval = 20) -> AXUIElement? {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if !isAppRunning {
                return nil
            }

            if usesInProcess, hasVisibleMenuWindow() {
                return AXUIElementCreateApplication(appPID)
            }

            let appElement = AXUIElementCreateApplication(appPID)
            if let window = findPontenWindow(in: appElement) {
                return window
            }

            waitInterval(0.2)
        }

        return nil
    }

    private func hasVisibleMenuWindow() -> Bool {
        NSApp.windows.contains {
            $0.title == "Ponten Menu" || $0.identifier?.rawValue == "PontenMenu"
        }
    }

    private func findPontenWindow(in appElement: AXUIElement) -> AXUIElement? {
        guard let windows = copyAttribute(appElement, attribute: kAXWindowsAttribute) as? [AXUIElement] else {
            return nil
        }

        for window in windows {
            let title = stringAttribute(window, attribute: kAXTitleAttribute) ?? ""
            let identifier = stringAttribute(window, attribute: kAXIdentifierAttribute) ?? ""
            if title == "Ponten Menu" || identifier == "PontenMenu" {
                return window
            }
        }

        return nil
    }

    func requireElement(
        in root: AXUIElement,
        role: String? = nil,
        title: String? = nil,
        titleContains: String? = nil,
        timeout: TimeInterval = 10
    ) throws -> AXUIElement {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let match = findDescendant(in: root, role: role, title: title, titleContains: titleContains) {
                return match
            }
            waitInterval(0.2)
        }

        let label = [role, title, titleContains].compactMap { $0 }.joined(separator: " / ")
        throw NSError(
            domain: "PontenE2E",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Required UI element was not found (\(label))."]
        )
    }

    func press(_ element: AXUIElement) throws {
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if error != .success {
            throw NSError(
                domain: "PontenE2E",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Failed to press element (AX error \(error.rawValue))."]
            )
        }
    }

    func waitForCheckBoxChecked(
        in root: AXUIElement,
        title: String,
        timeout: TimeInterval = 10
    ) throws -> AXUIElement {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let checkbox = findDescendant(in: root, role: kAXCheckBoxRole as String, title: title),
               boolAttribute(checkbox, attribute: kAXValueAttribute) == true {
                return checkbox
            }
            waitInterval(0.2)
        }

        throw NSError(
            domain: "PontenE2E",
            code: 6,
            userInfo: [NSLocalizedDescriptionKey: "Checkbox '\(title)' was not checked."]
        )
    }

    func waitForCopyMarker(dataDirectory: String, timeout: TimeInterval = 10) throws {
        let markerPath = URL(fileURLWithPath: dataDirectory).appendingPathComponent("e2e-last-copy.txt")
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if FileManager.default.fileExists(atPath: markerPath.path) {
                return
            }
            waitInterval(0.2)
        }

        throw NSError(
            domain: "PontenE2E",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "E2E copy marker file was not created."]
        )
    }

    static func assertAutoPastePersisted(dataDirectory: String, file: StaticString = #file, line: UInt = #line) {
        let indexPath = URL(fileURLWithPath: dataDirectory).appendingPathComponent("index.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexPath.path), file: file, line: line)

        guard let data = try? Data(contentsOf: indexPath),
              let json = String(data: data, encoding: .utf8) else {
            XCTFail("index.json could not be read.", file: file, line: line)
            return
        }

        XCTAssertTrue(
            json.contains("\"autoPaste\":true") || json.contains("\"autoPaste\": true"),
            "Expected autoPaste=true in index.json settings.",
            file: file,
            line: line
        )
    }

    static func seedSignature(dataDirectory: String, name: String = "Test Signature") throws {
        try FileManager.default.createDirectory(atPath: dataDirectory, withIntermediateDirectories: true)

        let signatureID = UUID()
        let filename = "\(signatureID.uuidString).png"
        let imagePath = URL(fileURLWithPath: dataDirectory).appendingPathComponent(filename)

        let image = NSImage(size: NSSize(width: 160, height: 80))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 160, height: 80)).fill()
        NSColor.black.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 3
        path.move(to: NSPoint(x: 20, y: 50))
        path.line(to: NSPoint(x: 140, y: 30))
        path.stroke()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PontenE2E", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to create seed PNG."])
        }
        try pngData.write(to: imagePath)

        struct SeedIndex: Codable {
            var items: [SeedItem]
            var activeID: UUID
            var settings: SeedSettings
        }
        struct SeedItem: Codable {
            var id: UUID
            var filename: String
            var name: String
        }
        struct SeedSettings: Codable {
            var autoPaste: Bool = false
        }

        let wrapper = SeedIndex(
            items: [SeedItem(id: signatureID, filename: filename, name: name)],
            activeID: signatureID,
            settings: SeedSettings()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let indexData = try encoder.encode(wrapper)
        try indexData.write(to: URL(fileURLWithPath: dataDirectory).appendingPathComponent("index.json"))
    }

    // MARK: - AX traversal

    private func findDescendant(
        in root: AXUIElement,
        role: String?,
        title: String?,
        titleContains: String? = nil
    ) -> AXUIElement? {
        var queue: [AXUIElement] = []
        if let children = copyAttribute(root, attribute: kAXChildrenAttribute) as? [AXUIElement] {
            queue.append(contentsOf: children)
        }

        while !queue.isEmpty {
            let element = queue.removeFirst()
            let elementRole = roleAttribute(element)
            let elementTitle = stringAttribute(element, attribute: kAXTitleAttribute)
                ?? stringAttribute(element, attribute: kAXDescriptionAttribute)

            let roleMatches = role == nil || elementRole == role
            let titleMatches: Bool
            if let title {
                titleMatches = elementTitle == title
            } else if let titleContains {
                titleMatches = elementTitle?.localizedCaseInsensitiveContains(titleContains) == true
            } else {
                titleMatches = true
            }

            if roleMatches && titleMatches && (role != nil || title != nil || titleContains != nil) {
                return element
            }

            if let children = copyAttribute(element, attribute: kAXChildrenAttribute) as? [AXUIElement] {
                queue.append(contentsOf: children)
            }
        }

        return nil
    }

    private func copyAttribute(_ element: AXUIElement, attribute: String) -> AnyObject? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return nil }
        return value
    }

    private func stringAttribute(_ element: AXUIElement, attribute: String) -> String? {
        copyAttribute(element, attribute: attribute) as? String
    }

    private func boolAttribute(_ element: AXUIElement, attribute: String) -> Bool? {
        if let number = copyAttribute(element, attribute: attribute) as? NSNumber {
            return number.boolValue
        }
        if let value = copyAttribute(element, attribute: attribute) as? String {
            return (value as NSString).boolValue
        }
        return nil
    }

    private func roleAttribute(_ element: AXUIElement) -> String? {
        stringAttribute(element, attribute: kAXRoleAttribute)
    }

    private static func withSerialization<T>(_ body: () throws -> T) throws -> T {
        let deadline = Date().addingTimeInterval(30)
        while !serializationLock.try() {
            guard Date() < deadline else {
                throw NSError(
                    domain: "PontenE2E",
                    code: 12,
                    userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for E2E serialization lock."]
                )
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        defer { serializationLock.unlock() }
        return try body()
    }

    /// Schedules UI work on the main queue and pumps `RunLoop.main` until it completes.
    /// Required for SwiftUI/AppKit hosting inside XCTest, which runs on the main thread.
    private func performOnMainWithRunLoop(_ block: @escaping () throws -> Void) throws {
        var thrown: Error?
        var completed = false
        let work = block

        DispatchQueue.main.async {
            do {
                try work()
            } catch {
                thrown = error
            }
            completed = true
        }

        let deadline = Date().addingTimeInterval(30)
        while !completed && Date() < deadline {
            pumpMainRunLoop(for: 0.05)
        }

        guard completed else {
            throw NSError(
                domain: "PontenE2E",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for main-thread UI work."]
            )
        }

        if let thrown { throw thrown }
    }

    private func waitInterval(_ interval: TimeInterval) {
        if usesInProcess || Thread.isMainThread {
            pumpMainRunLoop(for: interval)
        } else {
            Thread.sleep(forTimeInterval: interval)
        }
    }

    private func pumpMainRunLoop(for interval: TimeInterval) {
        let deadline = Date().addingTimeInterval(interval)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }
}

private extension NSRunningApplication {
    func waitUntilTerminated(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !isTerminated && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        return isTerminated
    }
}