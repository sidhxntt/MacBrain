import XCTest
@testable import MacBrain

@MainActor
final class ContextSafeguardsTests: XCTestCase {
    func testOneTurnTextContextIsVisibleBoundedAndConsumedAfterRequest() {
        let safeguards = ContextSafeguards()
        safeguards.enable(.clipboard, value: String(repeating: "x", count: 2_500))

        XCTAssertEqual(safeguards.visibleChips.map(\.kind), [.clipboard])
        XCTAssertEqual(safeguards.visibleChips.first?.preview.count, ContextAttachment.maximumCharacters)
        XCTAssertTrue(safeguards.promptContext.contains("Clipboard"))

        safeguards.consumeOneTurnAttachments()

        XCTAssertTrue(safeguards.visibleChips.isEmpty)
        XCTAssertTrue(safeguards.promptContext.isEmpty)
    }

    func testRepositoryContextRequiresRelevanceAndSurvivesOneTurnConsumption() {
        let safeguards = ContextSafeguards()
        safeguards.enable(.repository, value: "NotchBrain (main)")

        XCTAssertTrue(safeguards.promptContext(for: "What changed in this repository?").contains("NotchBrain"))
        XCTAssertTrue(safeguards.promptContext(for: "What is the weather?").isEmpty)

        safeguards.consumeOneTurnAttachments()
        XCTAssertEqual(safeguards.visibleChips.map(\.kind), [.repository])
    }

    func testPromptBudgetCapsHistoryAndContext() {
        let policy = PromptBudgetPolicy(maximumContextCharacters: 100, maximumHistoryMessages: 2)
        let attachments = [ContextAttachment(kind: .clipboard, value: String(repeating: "c", count: 500))]
        let history = [
            ChatMessage(role: .user, text: "one"),
            ChatMessage(role: .assistant, text: "two"),
            ChatMessage(role: .user, text: "three")
        ]

        XCTAssertEqual(policy.boundedContext(attachments).count, 100)
        XCTAssertEqual(policy.boundedHistory(history).map(\.text), ["two", "three"])
    }
}
