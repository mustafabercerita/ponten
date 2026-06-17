import AppKit
import XCTest

/// UI tests mirroring `PontenWPF.E2E.Tests` — launches real `Ponten.app` via XCUITest.
final class MenuBarUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["PONTEN_E2E"] = "1"
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testEmptyStateIsVisibleOnLaunch() throws {
        let dataDirectory = try makeDataDirectory()
        try launchApp(dataDirectory: dataDirectory)

        let window = app.windows["Ponten Menu"]
        XCTAssertTrue(window.waitForExistence(timeout: 15))
        XCTAssertTrue(window.staticTexts["No signatures yet."].waitForExistence(timeout: 5))
    }

    func testPreSeededSignatureAppearsInList() throws {
        let dataDirectory = try makeDataDirectory()
        try seedSignature(dataDirectory: dataDirectory, name: "E2E Signature")
        try launchApp(dataDirectory: dataDirectory)

        let window = app.windows["Ponten Menu"]
        XCTAssertTrue(window.waitForExistence(timeout: 15))
        XCTAssertTrue(window.buttons["E2E Signature"].waitForExistence(timeout: 5))
    }

    func testSignButtonShowsCopiedStatus() throws {
        let dataDirectory = try makeDataDirectory()
        try seedSignature(dataDirectory: dataDirectory)
        try launchApp(dataDirectory: dataDirectory)

        let window = app.windows["Ponten Menu"]
        XCTAssertTrue(window.waitForExistence(timeout: 15))
        window.buttons["Test Signature"].click()

        let signButton = window.buttons["Copy signature to clipboard"]
        XCTAssertTrue(signButton.waitForExistence(timeout: 5))
        signButton.click()

        try waitForCopyMarker(dataDirectory: dataDirectory)
    }

    func testAutoPasteTogglePersistsAcrossRestart() throws {
        let dataDirectory = try makeDataDirectory()
        try seedSignature(dataDirectory: dataDirectory)

        try launchApp(dataDirectory: dataDirectory)
        let window = app.windows["Ponten Menu"]
        XCTAssertTrue(window.waitForExistence(timeout: 15))

        let autoPaste = window.checkBoxes["Auto-paste after copying"]
        XCTAssertTrue(autoPaste.waitForExistence(timeout: 5))
        if !isCheckboxChecked(autoPaste) {
            autoPaste.click()
        }
        try waitForAutoPasteEnabled(dataDirectory: dataDirectory)

        window.buttons["Quit"].click()
        XCTAssertTrue(waitForWindowToClose(window, timeout: 5))
        try assertAutoPastePersisted(dataDirectory: dataDirectory)

        try launchApp(dataDirectory: dataDirectory)
        let restarted = app.windows["Ponten Menu"]
        XCTAssertTrue(restarted.waitForExistence(timeout: 15))
        XCTAssertTrue(restarted.buttons["Test Signature"].waitForExistence(timeout: 5))
        try assertAutoPastePersisted(dataDirectory: dataDirectory)

        let restartedAutoPaste = restarted.checkBoxes["Auto-paste after copying"]
        XCTAssertTrue(restartedAutoPaste.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForCheckboxChecked(restartedAutoPaste, timeout: 10))

        try? FileManager.default.removeItem(atPath: dataDirectory)
    }

    func testQuitButtonClosesApplication() throws {
        let dataDirectory = try makeDataDirectory()
        try launchApp(dataDirectory: dataDirectory)

        let window = app.windows["Ponten Menu"]
        XCTAssertTrue(window.waitForExistence(timeout: 15))
        window.buttons["Quit"].click()
        XCTAssertTrue(waitForWindowToClose(window, timeout: 5))
    }

    // MARK: - Helpers

    private func isCheckboxChecked(_ checkbox: XCUIElement) -> Bool {
        if let stringValue = checkbox.value as? String {
            return stringValue == "1" || stringValue.caseInsensitiveCompare("true") == .orderedSame
        }
        if let intValue = checkbox.value as? Int {
            return intValue == 1
        }
        if let numberValue = checkbox.value as? NSNumber {
            return numberValue.intValue == 1 || numberValue.boolValue
        }
        return checkbox.isSelected
    }

    private func waitForCheckboxChecked(_ checkbox: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isCheckboxChecked(checkbox) { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return isCheckboxChecked(checkbox)
    }

    private func waitForWindowToClose(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return !element.exists
    }

    private func launchApp(dataDirectory: String) throws {
        app.terminate()
        app = XCUIApplication()
        app.launchEnvironment["PONTEN_E2E"] = "1"
        app.launchEnvironment["PONTEN_DATA_DIR"] = dataDirectory
        app.launchArguments = ["--e2e", "--data-dir=\(dataDirectory)"]
        app.launch()
    }

    private func makeDataDirectory() throws -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("PontenE2E_\(UUID().uuidString)", isDirectory: true)
            .path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private func seedSignature(dataDirectory: String, name: String = "Test Signature") throws {
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
            throw NSError(domain: "PontenUI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create seed PNG."])
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
        try encoder.encode(wrapper).write(to: URL(fileURLWithPath: dataDirectory).appendingPathComponent("index.json"))
    }

    private func waitForCopyMarker(dataDirectory: String, timeout: TimeInterval = 10) throws {
        let markerPath = URL(fileURLWithPath: dataDirectory).appendingPathComponent("e2e-last-copy.txt")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: markerPath.path) { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw NSError(domain: "PontenUI", code: 2, userInfo: [NSLocalizedDescriptionKey: "E2E copy marker file was not created."])
    }

    private func waitForAutoPasteEnabled(dataDirectory: String, timeout: TimeInterval = 5) throws {
        let indexPath = URL(fileURLWithPath: dataDirectory).appendingPathComponent("index.json")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let data = try? Data(contentsOf: indexPath),
               let json = String(data: data, encoding: .utf8),
               json.contains("\"autoPaste\":true") || json.contains("\"autoPaste\": true") {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw NSError(domain: "PontenUI", code: 3, userInfo: [NSLocalizedDescriptionKey: "AutoPaste setting was not persisted to index.json."])
    }

    private func assertAutoPastePersisted(dataDirectory: String, file: StaticString = #file, line: UInt = #line) throws {
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
}