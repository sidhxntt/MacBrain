import XCTest
@testable import MacBrain

@MainActor
final class MacBrainWorkspaceViewTests: XCTestCase {
    func testDesktopWorkspaceCanBeConstructed() {
        _ = MacBrainWorkspaceView(coordinator: AppCoordinator())
    }

    func testDesktopWorkspaceUsesOnlyNativeSplitViewToggle() {
        XCTAssertFalse(MacBrainWorkspaceView.showsCustomSidebarToggle)
    }
}
