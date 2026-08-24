import AppKit
import XCTest
@testable import MacBrain

final class OverlayWindowPolicyTests: XCTestCase {
    func testSidebarPolicyJoinsEverySpaceAndSupportsFullScreenApps() {
        let behavior = OverlayWindowPolicy.sidebarCollectionBehavior
        let style = OverlayWindowPolicy.sidebarStyleMask

        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(behavior.contains(.moveToActiveSpace))
        XCTAssertFalse(style.contains(.nonactivatingPanel))
        XCTAssertTrue(style.contains(.resizable))
        XCTAssertEqual(OverlayWindowPolicy.level, .statusBar)
        XCTAssertEqual(
            OverlayWindowPolicy.clickShieldLevel.rawValue,
            OverlayWindowPolicy.level.rawValue - 1
        )
        XCTAssertFalse(OverlayWindowPolicy.clickShieldStyleMask.contains(.nonactivatingPanel))
    }

    func testActivationBarPolicyJoinsEverySpaceWithoutMovingAway() {
        let behavior = OverlayWindowPolicy.activationBarCollectionBehavior

        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(behavior.contains(.moveToActiveSpace))
    }

    func testDesktopAppUsesRegularActivationPolicy() {
        XCTAssertEqual(OverlayWindowPolicy.applicationActivationPolicy, .regular)
    }
}
