import AppKit
import XCTest
@testable import NotchBrain

final class SidebarGeometryTests: XCTestCase {
    func testRightEdgeFrameFitsVisibleDisplay() {
        let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let frame = SidebarGeometry.frame(in: visible, requestedWidth: 420, edge: .right)

        XCTAssertEqual(frame.maxX, visible.maxX - SidebarGeometry.edgeInset)
        XCTAssertEqual(frame.minY, visible.minY + SidebarGeometry.edgeInset)
        XCTAssertEqual(frame.height, visible.height - SidebarGeometry.edgeInset * 2)
    }

    func testLeftEdgeUsesVisibleFrameOriginOnSecondaryDisplay() {
        let visible = CGRect(x: 1920, y: 50, width: 1200, height: 800)
        let frame = SidebarGeometry.frame(in: visible, requestedWidth: 360, edge: .left)

        XCTAssertEqual(frame.minX, visible.minX + SidebarGeometry.edgeInset)
        XCTAssertEqual(frame.width, 360)
    }

    func testWidthClampsToMinimumAndMaximum() {
        let visible = CGRect(x: 0, y: 0, width: 1200, height: 800)

        XCTAssertEqual(
            SidebarGeometry.frame(in: visible, requestedWidth: 100, edge: .right).width,
            SidebarGeometry.minimumWidth
        )
        XCTAssertEqual(
            SidebarGeometry.frame(in: visible, requestedWidth: 1000, edge: .right).width,
            SidebarGeometry.maximumWidth
        )
    }

    func testNarrowDisplayNeverProducesFrameWiderThanAvailableArea() {
        let visible = CGRect(x: 0, y: 0, width: 300, height: 700)
        let frame = SidebarGeometry.frame(in: visible, requestedWidth: 560, edge: .right)

        XCTAssertEqual(frame.width, visible.width - SidebarGeometry.edgeInset * 2)
        XCTAssertGreaterThanOrEqual(frame.minX, visible.minX)
        XCTAssertLessThanOrEqual(frame.maxX, visible.maxX)
    }
}
