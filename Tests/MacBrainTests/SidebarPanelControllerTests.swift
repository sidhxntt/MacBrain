import XCTest
@testable import MacBrain

@MainActor
final class SidebarPanelControllerTests: XCTestCase {
    func testUsesInjectedChatStore() {
        let chatStore = ChatStore()
        let controller = SidebarPanelController(chatStore: chatStore)

        XCTAssertTrue(controller.chatStore === chatStore)
    }
}
