import XCTest
@testable import Ponten

final class ImageProcessorTests: XCTestCase {

    func testRemoveBackground() {
        let size = CGSize(width: 100, height: 100)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.black.setFill()
        NSRect(x: 40, y: 40, width: 20, height: 20).fill()
        image.unlockFocus()
        
        let processor = ImageProcessor()
        guard let result = try? processor.removeBackground(from: image) else {
            XCTFail("Failed to remove background")
            return
        }
        XCTAssertNotNil(result)
        // Basic check: should return a cropped image roughly the size of the black box (20x20)
        XCTAssertTrue(result.size.width < 50, "Cropping should have reduced the size")
    }

    func testThickenLines() {
        let size = CGSize(width: 50, height: 50)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.black.setFill()
        NSRect(x: 20, y: 20, width: 10, height: 10).fill()
        image.unlockFocus()

        let processor = ImageProcessor()
        guard let result = try? processor.thickenLines(in: image, amount: 5.0) else {
            XCTFail("Failed to thicken lines")
            return
        }
        XCTAssertNotNil(result)
        XCTAssertEqual(result.size, size)
    }
}
