import XCTest
@testable import Ponten

final class StorageErrorTests: XCTestCase {

    func testIsDiskFullDetectsPOSIXENOSPC() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXErrorCode.ENOSPC.rawValue))
        XCTAssertTrue(StorageError.isDiskFull(error))
    }

    func testIsDiskFullDetectsCocoaOutOfSpace() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        XCTAssertTrue(StorageError.isDiskFull(error))
    }

    func testUserFacingMessageReturnsDiskFullCopy() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXErrorCode.ENOSPC.rawValue))
        XCTAssertEqual(
            StorageError.userFacingMessage(for: error, fallbackPrefix: "Failed to save signatures"),
            "Not enough disk space to save signatures."
        )
    }

    func testUserFacingMessageFallsBackToLocalizedDescription() {
        let error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        XCTAssertEqual(
            StorageError.userFacingMessage(for: error, fallbackPrefix: "Failed to save signatures"),
            "Failed to save signatures: boom"
        )
    }
}