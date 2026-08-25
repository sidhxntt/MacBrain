import XCTest
@testable import MacBrain

final class MainWorkspaceSectionTests: XCTestCase {
    func testPrimarySidebarItemsExcludeBottomPinnedPreferences() {
        XCTAssertEqual(MainWorkspaceSection.primarySidebarItems, [.chats, .sources])
    }

    func testSettingsUsesSettingsLabel() {
        XCTAssertEqual(MainWorkspaceSection.preferences.title, "Settings")
    }
}
