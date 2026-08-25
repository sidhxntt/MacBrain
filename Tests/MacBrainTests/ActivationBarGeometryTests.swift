import XCTest
@testable import MacBrain

final class ActivationBarGeometryTests: XCTestCase {
    func testVerticalHandleUsesCompactDimensions() {
        XCTAssertEqual(ActivationBarGeometry.size, CGSize(width: 9, height: 58))
    }

    func testVerticalHandleIsPinnedToTheRightEdge() {
        let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let frame = ActivationBarGeometry.frame(in: visible, centerY: 400)

        XCTAssertEqual(frame.maxX, visible.maxX - ActivationBarGeometry.edgeInset)
        XCTAssertEqual(frame.midY, 400, accuracy: 0.001)
    }

    func testVerticalDragClampsAtTheTopAndBottomOfTheVisibleFrame() {
        let visible = CGRect(x: -1200, y: 50, width: 1200, height: 800)
        let topFrame = ActivationBarGeometry.frame(in: visible, centerY: -500)
        let bottomFrame = ActivationBarGeometry.frame(in: visible, centerY: 2_000)

        XCTAssertEqual(topFrame.minY, visible.minY + ActivationBarGeometry.edgeInset)
        XCTAssertEqual(bottomFrame.maxY, visible.maxY - ActivationBarGeometry.edgeInset)
    }
}
