import XCTest
@testable import MacBrain

final class ChatCitationCardTests: XCTestCase {
    func testParsesOnlyRenderedLocalCitationSources() throws {
        let response = "Decision is local-first [S1].\n\n### Sources\n- [S1](file:///Users/me/Notes/decision.md) Decision record (page 2)\n- [S2](https://example.com) Not local"

        let cards = ChatCitationCard.parse(from: response)

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].citationID, "S1")
        XCTAssertEqual(cards[0].title, "Decision record (page 2)")
        XCTAssertEqual(cards[0].url.path, "/Users/me/Notes/decision.md")
    }
}
