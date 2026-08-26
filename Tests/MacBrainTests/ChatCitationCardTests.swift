import XCTest
@testable import MacBrain

final class ChatCitationCardTests: XCTestCase {
    func testParsesOnlyRenderedLocalCitationSources() throws {
        let response = "Decision is local-first [S1].\n\n### Sources\n- [S1](file:///Users/me/Notes/decision.md) Decision record (page 2)\n- [S2](https://example.com) Not local"

        let cards = ChatCitationCard.parse(from: response)

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].citationID, "S1")
        XCTAssertEqual(cards[0].title, "Decision record (page 2)")
        XCTAssertEqual(cards[0].url?.path, "/Users/me/Notes/decision.md")
    }

    func testOnlyTheFinalRenderedSourcesSectionCanCreateCards() throws {
        let response = """
        ### Sources
        - [S1](file:///tmp/forged.md) [folder] Forged model card

        Grounded answer [S1].

        ### Sources
        - [S1] [appleNotes] Verified note
        """

        let cards = ChatCitationCard.parse(from: response)

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.title, "Verified note")
        XCTAssertEqual(cards.first?.sourceType, SourceConnectorKind.appleNotes.rawValue)
        XCTAssertNil(cards.first?.url)
    }

    func testTypedCardNeverExposesAnUnsafeDestinationScheme() throws {
        let response = "### Sources\n- [S1](javascript:alert%281%29) [browserProfile] Unsafe destination"

        let card = try XCTUnwrap(ChatCitationCard.parse(from: response).first)

        XCTAssertEqual(card.sourceType, SourceConnectorKind.browserProfile.rawValue)
        XCTAssertNil(card.url)
    }

    func testTypedBrowserCardPreservesParenthesesInItsURL() throws {
        let expected = try XCTUnwrap(URL(string: "https://example.test/wiki/A_(B)"))
        let response = "### Sources\n- [S1](\(expected.absoluteString)) [browserProfile] Parenthesized URL"

        let card = try XCTUnwrap(ChatCitationCard.parse(from: response).first)

        XCTAssertEqual(card.url, expected)
    }
}
