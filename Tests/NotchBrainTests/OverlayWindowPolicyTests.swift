import AppKit
import XCTest
@testable import NotchBrain

final class OverlayWindowPolicyTests: XCTestCase {
    func testSidebarPolicyJoinsEverySpaceAndSupportsFullScreenApps() {
        let behavior = OverlayWindowPolicy.sidebarCollectionBehavior
        let style = OverlayWindowPolicy.sidebarStyleMask

        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(behavior.contains(.moveToActiveSpace))
        XCTAssertTrue(style.contains(.nonactivatingPanel))
        XCTAssertTrue(style.contains(.resizable))
        XCTAssertEqual(OverlayWindowPolicy.level, .statusBar)
    }

    func testActivationBarPolicyJoinsEverySpaceWithoutMovingAway() {
        let behavior = OverlayWindowPolicy.activationBarCollectionBehavior

        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(behavior.contains(.moveToActiveSpace))
    }
}
