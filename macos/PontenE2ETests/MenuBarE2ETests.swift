import ApplicationServices
import XCTest

/// Category: E2E — serialized menu-bar UI tests mirroring `PontenWPF.E2E.Tests`.
/// These tests launch the real `Ponten.app` bundle and drive the UI via AXUIElement.
final class MenuBarE2ETests: XCTestCase {

    // MARK: - E2E

    func testEmptyStateIsVisibleOnLaunch() throws {
        let fixture = try E2ETestFixture()
        defer { _ = fixture }

        guard let window = fixture.waitForMainWindow() else {
            XCTFail("Ponten main window was not found.")
            return
        }

        let emptyState = try fixture.requireElement(
            in: window,
            titleContains: "No signatures yet."
        )
        XCTAssertNotNil(emptyState)
    }

    func testPreSeededSignatureAppearsInList() throws {
        let dataDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PontenE2E_\(UUID().uuidString)", isDirectory: true)
            .path
        try E2ETestFixture.seedSignature(dataDirectory: dataDirectory, name: "E2E Signature")

        let fixture = try E2ETestFixture(dataDirectory: dataDirectory)
        defer { _ = fixture }

        guard let window = fixture.waitForMainWindow() else {
            XCTFail("Ponten main window was not found.")
            return
        }

        let listItem = try fixture.requireElement(in: window, title: "E2E Signature")
        XCTAssertNotNil(listItem)
    }

    func testSignButtonShowsCopiedStatus() throws {
        let dataDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PontenE2E_\(UUID().uuidString)", isDirectory: true)
            .path
        try E2ETestFixture.seedSignature(dataDirectory: dataDirectory)

        let fixture = try E2ETestFixture(dataDirectory: dataDirectory)
        defer { _ = fixture }

        guard let window = fixture.waitForMainWindow() else {
            XCTFail("Ponten main window was not found.")
            return
        }

        let signatureItem = try fixture.requireElement(in: window, title: "Test Signature")
        try fixture.press(signatureItem)

        let signButton = try fixture.requireElement(
            in: window,
            role: kAXButtonRole as String,
            title: "Sign"
        )
        try fixture.press(signButton)

        try fixture.waitForCopyMarker(dataDirectory: dataDirectory)
    }

    func testAutoPasteTogglePersistsAcrossRestart() throws {
        let dataDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PontenE2E_\(UUID().uuidString)", isDirectory: true)
            .path
        try E2ETestFixture.seedSignature(dataDirectory: dataDirectory)

        do {
            let fixture = try E2ETestFixture(dataDirectory: dataDirectory)
            guard let window = fixture.waitForMainWindow() else {
                XCTFail("Ponten main window was not found.")
                return
            }

            let autoPaste = try fixture.requireElement(
                in: window,
                role: kAXCheckBoxRole as String,
                title: "Auto-paste after copying"
            )

            if fixture.boolValue(for: autoPaste) != true {
                try fixture.press(autoPaste)
            }

            try waitForAutoPasteEnabled(dataDirectory: dataDirectory)

            let quitButton = try fixture.requireElement(
                in: window,
                role: kAXButtonRole as String,
                title: "Quit"
            )
            try fixture.press(quitButton)
            try waitForProcessExit(fixture.process, timeout: 10)
            E2ETestFixture.assertAutoPastePersisted(dataDirectory: dataDirectory)
        }

        let restarted = try E2ETestFixture(dataDirectory: dataDirectory)
        defer { _ = restarted }

        guard let restartedWindow = restarted.waitForMainWindow() else {
            XCTFail("Ponten main window was not found after restart.")
            return
        }

        _ = try restarted.requireElement(in: restartedWindow, title: "Test Signature")
        E2ETestFixture.assertAutoPastePersisted(dataDirectory: dataDirectory)

        let restartedAutoPaste = try restarted.waitForCheckBoxChecked(
            in: restartedWindow,
            title: "Auto-paste after copying"
        )
        XCTAssertEqual(restarted.boolValue(for: restartedAutoPaste), true)

        try? FileManager.default.removeItem(atPath: dataDirectory)
    }

    func testQuitButtonClosesApplication() throws {
        let fixture = try E2ETestFixture()
        defer { _ = fixture }

        guard let window = fixture.waitForMainWindow() else {
            XCTFail("Ponten main window was not found.")
            return
        }

        let quitButton = try fixture.requireElement(
            in: window,
            role: kAXButtonRole as String,
            title: "Quit"
        )
        try fixture.press(quitButton)

        XCTAssertTrue(try waitForProcessExit(fixture.process, timeout: 10))
    }

    // MARK: - Helpers

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

        throw NSError(
            domain: "PontenE2E",
            code: 9,
            userInfo: [NSLocalizedDescriptionKey: "AutoPaste setting was not persisted to index.json."]
        )
    }

    @discardableResult
    private func waitForProcessExit(_ process: Process?, timeout: TimeInterval) throws -> Bool {
        guard let process else { return true }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            throw NSError(
                domain: "PontenE2E",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Ponten process did not exit."]
            )
        }
        return true
    }
}

private extension E2ETestFixture {
    func boolValue(for element: AXUIElement) -> Bool? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute, &value) == .success else {
            return nil
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            return (string as NSString).boolValue
        }
        return nil
    }
}