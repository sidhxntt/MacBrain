import XCTest
@testable import MacBrain

@MainActor
final class MainWorkspaceStoreTests: XCTestCase {
    func testStartsOnChats() {
        XCTAssertEqual(MainWorkspaceStore().selection, .chats)
    }

    func testSidebarIsDisabledUntilUserEnablesIt() {
        let store = MainWorkspaceStore()

        XCTAssertFalse(store.isSidebarEnabled)

        store.enableSidebar()

        XCTAssertTrue(store.isSidebarEnabled)
    }

    func testNavigationSidebarStartsVisibleAndCanToggle() {
        let store = MainWorkspaceStore()

        XCTAssertTrue(store.isNavigationSidebarVisible)

        store.toggleNavigationSidebar()

        XCTAssertFalse(store.isNavigationSidebarVisible)
    }

    func testNavigationSidebarCanFollowNativeSplitViewVisibility() {
        let store = MainWorkspaceStore()

        store.setNavigationSidebarVisible(false)

        XCTAssertFalse(store.isNavigationSidebarVisible)
    }

}
