import Testing
@testable import MacBrain

struct SourceQueryScopeTests {
    struct ScopeCase: Sendable, CustomTestStringConvertible {
        let prompt: String
        let expected: Set<SourceConnectorKind>

        var testDescription: String { prompt }
    }

    @Test(
        "Explicit connector wording resolves to the named source kind",
        arguments: [
            ScopeCase(prompt: "Search my Apple Notes for AURORA", expected: [.appleNotes]),
            ScopeCase(prompt: "Find the AURORA email in my Mail", expected: [.appleMail]),
            ScopeCase(prompt: "Which AURORA event is on my calendar?", expected: [.calendar]),
            ScopeCase(prompt: "Which AURORA item is in my reminders?", expected: [.reminders]),
            ScopeCase(prompt: "Find AURORA in my contacts", expected: [.contacts]),
            ScopeCase(prompt: "Find AURORA in my browser history", expected: [.browserProfile]),
            ScopeCase(prompt: "Who said AURORA in my Messages?", expected: [.messages]),
            ScopeCase(prompt: "Find AURORA in my Photos metadata", expected: [.photos]),
            ScopeCase(prompt: "Which AURORA title is in my Apple Books library?", expected: [.books]),
            ScopeCase(prompt: "Find AURORA in my connected folder", expected: [.folder]),
            ScopeCase(prompt: "Find AURORA in this Git repository", expected: [.gitRepository]),
            ScopeCase(prompt: "SEARCH MY NOTES AND MAIL FOR AURORA", expected: [.appleNotes, .appleMail]),
        ]
    )
    func resolvesNamedConnector(item: ScopeCase) {
        #expect(SourceQueryScope.resolve(prompt: item.prompt) == item.expected)
    }

    @Test(
        "Source-like public questions remain general and never activate local retrieval",
        arguments: [
            "How does Apple Mail work?",
            "What is a git repository?",
            "Explain browser history databases",
            "How do calendars calculate leap years?",
            "What is a contact lens made from?",
            "Explain the Photos framework",
            "Suggest a science-fiction book",
        ]
    )
    func publicKnowledgeRemainsGeneral(prompt: String) {
        let route = ChatQueryIntentRouter().route(prompt: prompt, conversation: [])
        #expect(route.intent == .general)
    }

    @Test("No explicit source wording has no scope")
    func ordinaryLocalFactHasNoForcedScope() {
        #expect(SourceQueryScope.resolve(prompt: "Who owns the Aurora beta decision?") == nil)
    }
}
