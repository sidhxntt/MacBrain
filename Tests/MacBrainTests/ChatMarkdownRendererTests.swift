import XCTest
@testable import MacBrain

final class ChatMarkdownRendererTests: XCTestCase {
    func testRendersMarkdownWithoutSyntaxMarkers() {
        let rendered = ChatMarkdownRenderer.render("**MacBook Pro** with `M5 Pro`")

        XCTAssertEqual(String(rendered.characters), "MacBook Pro with M5 Pro")
    }
}
