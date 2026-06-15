import XCTest
@testable import Ponten

final class SignatureManagerTests: XCTestCase {

    var manager: SignatureManager!
    var testDirectory: URL!

    // MARK: - Setup / Teardown

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Use a fresh temp directory per test so tests are isolated
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PontenTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)

        // We test via the shared singleton because SignatureManager is a singleton.
        // Clean state before each test.
        manager = SignatureManager.shared
        deleteAllSignatures()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: testDirectory)
        deleteAllSignatures()
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    /// Creates a minimal valid 1x1 PNG in the test directory.
    private func makePNGFile(named name: String = "test_signature.png") throws -> URL {
        let url = testDirectory.appendingPathComponent(name)
        let image = NSImage(size: NSSize(width: 200, height: 80))
        image.lockFocus()
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

    private func deleteAllSignatures() {
        for id in manager.signatures.map(\.item.id) {
            manager.deleteSignature(id: id)
        }
    }

    // MARK: - Tests

    func testInitialStateHasNoSignature() {
        XCTAssertNil(manager.signatureImage, "Should start with no signature after delete")
    }

    func testSaveValidPNGLoadsImage() throws {
        let url = try makePNGFile()
        XCTAssertNoThrow(try manager.saveSignature(from: url))

        // Allow a moment for async @Published update
        let expectation = XCTestExpectation(description: "signatureImage set")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertNotNil(self.manager.signatureImage)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testSaveInvalidPathThrowsError() {
        let badURL = URL(fileURLWithPath: "/nonexistent/path/signature.png")
        XCTAssertThrowsError(try manager.saveSignature(from: badURL)) { error in
            XCTAssertTrue(error is SignatureError)
        }
    }

    func testDeleteSignatureClearsImage() throws {
        let url = try makePNGFile()
        try manager.saveSignature(from: url)

        let setExpectation = XCTestExpectation(description: "image set")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.manager.deleteSignature()
            setExpectation.fulfill()
        }
        wait(for: [setExpectation], timeout: 1.0)

        let deleteExpectation = XCTestExpectation(description: "image cleared")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            XCTAssertNil(self.manager.signatureImage)
            deleteExpectation.fulfill()
        }
        wait(for: [deleteExpectation], timeout: 1.0)
    }

    func testCopyToClipboardReturnsFalseWithNoSignature() {
        manager.deleteSignature()
        let result = manager.copySignatureToClipboard()
        XCTAssertFalse(result, "Should return false when no signature is set")
    }

    func testCopyToClipboardReturnsTrueWithSignature() throws {
        let url = try makePNGFile()
        try manager.saveSignature(from: url)

        let expectation = XCTestExpectation(description: "clipboard copy")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let result = self.manager.copySignatureToClipboard()
            XCTAssertTrue(result)
            // Verify pasteboard actually has image data
            let hasImage = NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil)
            XCTAssertTrue(hasImage, "Pasteboard should contain an image")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    func testToastMessageClearsAfterDelay() throws {
        manager.showToast("Test toast")

        let predicateSet = NSPredicate { _, _ in
            return SignatureManager.shared.toastMessage != nil
        }
        let expSet = XCTNSPredicateExpectation(predicate: predicateSet, object: nil)
        wait(for: [expSet], timeout: 2.0)

        let predicateClear = NSPredicate { _, _ in
            return SignatureManager.shared.toastMessage == nil
        }
        let expClear = XCTNSPredicateExpectation(predicate: predicateClear, object: nil)
        wait(for: [expClear], timeout: 5.0)
    }

    func testReplacingSignatureUpdatesImage() throws {
        let url1 = try makePNGFile(named: "sig1.png")
        let url2 = try makePNGFile(named: "sig2.png")

        try manager.saveSignature(from: url1)

        let predicate1 = NSPredicate { _, _ in
            return SignatureManager.shared.signatureImage != nil
        }
        let exp1 = XCTNSPredicateExpectation(predicate: predicate1, object: nil)
        wait(for: [exp1], timeout: 5.0)

        try manager.saveSignature(from: url2)

        let exp2 = XCTestExpectation(description: "Wait for background thread to process second signature")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            exp2.fulfill()
        }
        wait(for: [exp2], timeout: 3.0)
        
        XCTAssertNotNil(manager.signatureImage)
    }

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
}
