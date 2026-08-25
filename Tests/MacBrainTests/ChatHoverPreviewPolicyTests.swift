import XCTest
@testable import MacBrain

final class ChatHoverPreviewPolicyTests: XCTestCase {
    func testShowsPreviewOnlyForTruncatedTitles() {
        XCTAssertFalse(ChatHoverPreviewPolicy.shouldShowPreview(for: "Short title"))
        XCTAssertTrue(ChatHoverPreviewPolicy.shouldShowPreview(for: String(repeating: "Long title ", count: 8)))
    }

    func testScrollsOnlyTitlesThatNeedMoreSidebarRoom() {
        XCTAssertFalse(ChatHoverPreviewPolicy.shouldAutoScrollTitle(for: "Short title"))
        XCTAssertTrue(ChatHoverPreviewPolicy.shouldAutoScrollTitle(for: String(repeating: "Long title ", count: 8)))
    }

    func testUsesMostRecentMessageAsPreviewText() {
        let session = ChatSession(
            title: "Long project discussion that does not fit in sidebar",
            messages: [ChatMessage(role: .user, text: "First"), ChatMessage(role: .assistant, text: "Latest local answer")]
        )

        XCTAssertEqual(ChatHoverPreviewPolicy.previewText(for: session), "Latest local answer")
    }
}
