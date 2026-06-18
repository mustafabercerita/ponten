import XCTest
@testable import Ponten

@MainActor
final class SignatureManagerTests: XCTestCase {

    var manager: SignatureManager!
    var testStore: SignatureStore!
    var testDirectory: URL!

    // MARK: - Setup / Teardown

    override func setUpWithError() throws {
        try super.setUpWithError()
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PontenTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)

        testStore = SignatureStore(storageDirectory: testDirectory)
        manager = SignatureManager(store: testStore)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: testDirectory)
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    /// Creates a minimal valid PNG with white edges in the test directory.
    private func makePNGFile(named name: String = "test_signature.png") throws -> URL {
        let url = testDirectory.appendingPathComponent(name)
        let image = NSImage(size: NSSize(width: 200, height: 80))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 200, height: 80)).fill()
        NSColor.black.setFill()
        NSBezierPath(rect: NSRect(x: 10, y: 30, width: 180, height: 20)).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw XCTSkip("Could not create test PNG — skipping")
        }
        try png.write(to: url)
        return url
    }

    // MARK: - Tests

    @MainActor
    func testInitialStateHasNoSignature() {
        XCTAssertNil(manager.signatureImage, "Should start with no signature")
    }

    @MainActor
    func testSaveValidPNGLoadsImage() throws {
        let url = try makePNGFile()
        XCTAssertNoThrow(try manager.saveSignature(from: url))
        XCTAssertNotNil(manager.signatureImage)
    }

    @MainActor
    func testSaveInvalidPathThrowsError() {
        let badURL = URL(fileURLWithPath: "/nonexistent/path/signature.png")
        XCTAssertThrowsError(try manager.saveSignature(from: badURL)) { error in
            XCTAssertTrue(error is SignatureError)
        }
    }

    @MainActor
    func testDeleteSignatureClearsImage() throws {
        let url = try makePNGFile()
        try manager.saveSignature(from: url)
        XCTAssertNotNil(manager.signatureImage)

        manager.deleteSignature()
        XCTAssertNil(manager.signatureImage)
    }

    @MainActor
    func testCopyToClipboardReturnsFalseWithNoSignature() {
        let result = manager.copySignatureToClipboard()
        XCTAssertFalse(result, "Should return false when no signature is set")
    }

    @MainActor
    func testCopyToClipboardReturnsTrueWithSignature() throws {
        let url = try makePNGFile()
        try manager.saveSignature(from: url)
        XCTAssertNotNil(manager.signatureImage)

        let result = manager.copySignatureToClipboard()
        XCTAssertTrue(result)
        let hasImage = NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil)
        XCTAssertTrue(hasImage, "Pasteboard should contain an image")
    }

    @MainActor
    func testToastMessageClearsAfterDelay() {
        manager.toastDuration = 0.3
        manager.showToast("Test toast")
        XCTAssertEqual(manager.toastMessage, "Test toast")

        let exp = expectation(description: "toast clears")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertNil(self.manager.toastMessage)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    @MainActor
    func testReplacingSignatureUpdatesImage() throws {
        let url1 = try makePNGFile(named: "sig1.png")
        let url2 = try makePNGFile(named: "sig2.png")

        try manager.saveSignature(from: url1)
        XCTAssertNotNil(manager.signatureImage)
        let firstID = try XCTUnwrap(manager.activeSignatureID)

        try manager.saveSignature(from: url2)
        XCTAssertNotNil(manager.signatureImage)
        XCTAssertNotEqual(manager.activeSignatureID, firstID)
    }

    @MainActor
    func testSaveIndexPersistsActiveID() throws {
        let url = try makePNGFile()
        try manager.saveSignature(from: url)
        let activeID = try XCTUnwrap(manager.activeSignatureID)

        XCTAssertEqual(testStore.loadActiveID(), activeID)
        XCTAssertEqual(testStore.load().signatures.count, 1)
    }

    @MainActor
    func testLoadPrunesMissingPNGEntries() throws {
        let existingID = UUID()
        let missingID = UUID()
        let existingItem = SignatureItem(id: existingID, filename: "exists.png")
        let missingItem = SignatureItem(id: missingID, filename: "missing.png")
        try testStore.saveIndex(items: [existingItem, missingItem], activeID: missingID)
        _ = try makePNGFile(named: "exists.png")

        let reloadedStore = SignatureStore(storageDirectory: testDirectory)
        let result = reloadedStore.load()

        XCTAssertEqual(result.signatures.count, 1)
        XCTAssertEqual(result.prunedCount, 1)
        XCTAssertEqual(result.signatures.first?.0.id, existingID)
        XCTAssertEqual(reloadedStore.loadActiveID(), existingID)
    }

    @MainActor
    func testLoadShowsToastWhenPNGsMissing() throws {
        let existingID = UUID()
        let missingID = UUID()
        let existingItem = SignatureItem(id: existingID, filename: "exists.png")
        let missingItem = SignatureItem(id: missingID, filename: "missing.png")
        try testStore.saveIndex(items: [existingItem, missingItem], activeID: missingID)
        _ = try makePNGFile(named: "exists.png")

        let reloadedManager = SignatureManager(store: SignatureStore(storageDirectory: testDirectory))
        XCTAssertEqual(reloadedManager.toastMessage, "1 signature removed — image file(s) missing")
    }

    @MainActor
    func testDeletingInactiveSignatureKeepsActiveSignature() throws {
        let url1 = try makePNGFile(named: "sig1.png")
        let url2 = try makePNGFile(named: "sig2.png")

        try manager.saveSignature(from: url1)
        let firstID = try XCTUnwrap(manager.activeSignatureID)

        try manager.saveSignature(from: url2)
        let activeID = try XCTUnwrap(manager.activeSignatureID)
        XCTAssertNotEqual(firstID, activeID)

        manager.deleteSignature(id: firstID)

        XCTAssertEqual(manager.activeSignatureID, activeID)
        XCTAssertNotNil(manager.signatureImage)
    }

    @MainActor
    func testSelectActiveSignaturePersistsToIndex() throws {
        let url1 = try makePNGFile(named: "sig1.png")
        let url2 = try makePNGFile(named: "sig2.png")

        try manager.saveSignature(from: url1)
        let firstID = try XCTUnwrap(manager.activeSignatureID)

        try manager.saveSignature(from: url2)
        let secondID = try XCTUnwrap(manager.activeSignatureID)
        XCTAssertNotEqual(firstID, secondID)

        manager.selectActiveSignature(id: firstID)
        XCTAssertEqual(manager.activeSignatureID, firstID)
        XCTAssertEqual(testStore.loadActiveID(), firstID)
    }

    @MainActor
    func testCorruptIndexRebuildsFromPNGFiles() throws {
        let id = UUID()
        let filename = "\(id.uuidString).png"
        _ = try makePNGFile(named: filename)
        try "not json".write(to: testDirectory.appendingPathComponent("index.json"), atomically: true, encoding: .utf8)

        let reloadedStore = SignatureStore(storageDirectory: testDirectory)
        let result = reloadedStore.load()

        XCTAssertEqual(result.signatures.count, 1)
        XCTAssertEqual(result.signatures.first?.0.id, id)
        XCTAssertEqual(reloadedStore.loadActiveID(), id)
    }

    @MainActor
    func testCorruptIndexPreservesSettingsFromPartialJSON() throws {
        let id = UUID()
        let filename = "\(id.uuidString).png"
        _ = try makePNGFile(named: filename)
        let corruptJSON = """
        {
          "items": "not-an-array",
          "settings": {
            "launchAtLogin": true,
            "autoPaste": false,
            "removeBackground": false
          }
        }
        """
        try corruptJSON.write(
            to: testDirectory.appendingPathComponent("index.json"),
            atomically: true,
            encoding: .utf8
        )

        let reloadedStore = SignatureStore(storageDirectory: testDirectory)
        let result = reloadedStore.load()

        XCTAssertEqual(result.signatures.count, 1)
        let settings = try XCTUnwrap(reloadedStore.loadSettings())
        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertFalse(settings.autoPaste)
        XCTAssertFalse(settings.removeBackground)
    }

    @MainActor
    func testMissingIndexUsesLegacyMigration() throws {
        _ = try makePNGFile(named: "signature.png")

        let reloadedStore = SignatureStore(storageDirectory: testDirectory)
        let result = reloadedStore.load()

        XCTAssertEqual(result.signatures.count, 1)
        XCTAssertEqual(result.signatures.first?.0.filename, "signature.png")
        XCTAssertNotNil(reloadedStore.loadActiveID())
    }

    @MainActor
    func testRenameSignatureUpdatesPublishedState() throws {
        let url = try makePNGFile()
        try manager.saveSignature(from: url)
        let id = try XCTUnwrap(manager.activeSignatureID)

        manager.renameSignature(id: id, newName: "Work Sig")

        XCTAssertEqual(manager.signatures.first?.item.name, "Work Sig")
    }

    @MainActor
    func testDeleteRemovesFileAfterIndexSave() throws {
        let url = try makePNGFile()
        try manager.saveSignature(from: url)
        let id = try XCTUnwrap(manager.activeSignatureID)
        let filename = try XCTUnwrap(manager.signatures.first?.item.filename)
        let filePath = testDirectory.appendingPathComponent(filename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath.path))

        manager.deleteSignature(id: id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: filePath.path))
        XCTAssertEqual(testStore.load().signatures.count, 0)
    }

    @MainActor
    func testSaveWritesTempFileThenCommitsFinalPNG() throws {
        let url = try makePNGFile()
        try manager.saveSignature(from: url)
        let filename = try XCTUnwrap(manager.signatures.first?.item.filename)

        XCTAssertTrue(FileManager.default.fileExists(atPath: testDirectory.appendingPathComponent(filename).path))
        let tempFiles = try FileManager.default.contentsOfDirectory(at: testDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".tmp.png") }
        XCTAssertTrue(tempFiles.isEmpty, "Temp PNG files should be cleaned up after save")
    }

    @MainActor
    func testReadsWindowsStylePascalCaseJSON() throws {
        let id = UUID()
        let pascalCaseJSON = """
        {
          "Items": [
            { "Id": "\(id.uuidString)", "Filename": "windows.png", "Name": "Windows" }
          ],
          "ActiveID": "\(id.uuidString)",
          "Settings": {
            "LaunchAtLogin": false,
            "AutoPaste": true,
            "RemoveBackground": false
          }
        }
        """
        try pascalCaseJSON.write(
            to: testDirectory.appendingPathComponent("index.json"),
            atomically: true,
            encoding: .utf8
        )
        _ = try makePNGFile(named: "windows.png")

        let store = SignatureStore(storageDirectory: testDirectory)
        let result = store.load()

        XCTAssertEqual(result.signatures.count, 1)
        XCTAssertEqual(result.signatures.first?.0.id, id)
        XCTAssertEqual(store.loadActiveID(), id)

        let settings = try XCTUnwrap(store.loadSettings())
        XCTAssertTrue(settings.autoPaste)
        XCTAssertFalse(settings.removeBackground)
    }

    func testLoadsIndexWithPartialSettingsLikeUITestSeed() throws {
        let id = UUID()
        let filename = "\(id.uuidString).png"
        let partialSettingsJSON = """
        {
          "activeID": "\(id.uuidString)",
          "items": [
            { "id": "\(id.uuidString)", "filename": "\(filename)", "name": "E2E Signature" }
          ],
          "settings": { "autoPaste": false }
        }
        """
        try partialSettingsJSON.write(
            to: testDirectory.appendingPathComponent("index.json"),
            atomically: true,
            encoding: .utf8
        )
        _ = try makePNGFile(named: filename)

        let store = SignatureStore(storageDirectory: testDirectory)
        let result = store.load()

        XCTAssertEqual(result.signatures.count, 1)
        XCTAssertEqual(result.signatures.first?.0.name, "E2E Signature")
        XCTAssertEqual(store.loadSettings()?.autoPaste, false)
        XCTAssertEqual(store.loadSettings()?.launchAtLogin, false)
        XCTAssertEqual(store.loadSettings()?.removeBackground, true)
    }

    func testSettingsRoundTripInIndexJson() throws {
        manager.autoPaste = false
        manager.removeBackground = false

        let url = try makePNGFile()
        try manager.saveSignature(from: url)

        let reloaded = SignatureManager(store: SignatureStore(storageDirectory: testDirectory))
        XCTAssertFalse(reloaded.autoPaste)
        XCTAssertFalse(reloaded.removeBackground)

        let indexData = try Data(contentsOf: testDirectory.appendingPathComponent("index.json"))
        let json = String(data: indexData, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"settings\""))
        XCTAssertTrue(json.contains("\"autoPaste\":false") || json.contains("\"autoPaste\": false"))
        XCTAssertTrue(json.contains("\"removeBackground\":false") || json.contains("\"removeBackground\": false"))
        XCTAssertTrue(json.contains("\"launchAtLogin\""))
    }
}