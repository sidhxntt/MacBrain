import Testing
@testable import MacBrain

struct LocalQueryPlannerTests {
    @Test(
        "Note count paraphrases produce the same structured plan",
        arguments: [
            "How many notes do I have?",
            "What is the total number of Apple Notes?",
            "Give me my note count",
        ]
    )
    func plansNotesCount(prompt: String) {
        let plan = LocalQueryPlanner().plan(prompt: prompt, records: [], conversation: [])
        #expect(plan == .connector(.count, scope: [.appleNotes]))
    }

    @Test("First-person Photos index count is a structured Photos query")
    func plansPhotosIndexCount() {
        let plan = LocalQueryPlanner().plan(
            prompt: "How many photos do I have indexed?",
            records: [],
            conversation: []
        )

        #expect(plan == .connector(.count, scope: [.photos]))
    }

    @Test("Public Photos-framework counts do not activate a local source")
    func publicPhotosCountRemainsEvidenceSearch() {
        let plan = LocalQueryPlanner().plan(
            prompt: "How many photos can the Photos framework fetch?",
            records: [],
            conversation: []
        )

        #expect(plan == .evidenceSearch(scope: nil))
    }

    @Test(
        "Natural content questions always reach the evidence probe",
        arguments: [
            "Who sent the message about ORBIT?",
            "What did the conversation decide?",
            "Summarize the launch handoff",
            "What is the capital of Japan?",
        ]
    )
    func naturalContentQuestionsProbeEvidence(prompt: String) {
        let plan = LocalQueryPlanner().plan(prompt: prompt, records: [], conversation: [])
        #expect(plan == .evidenceSearch(scope: nil))
    }

    @Test
    func explicitSourcesOnlyNarrowEvidenceScope() {
        let plan = LocalQueryPlanner().plan(
            prompt: "Compare ORBIT in Notes and Mail",
            records: [],
            conversation: []
        )
        #expect(plan == .evidenceSearch(scope: [.appleNotes, .appleMail]))
    }

    @Test(
        "Every connector has user-facing vocabulary",
        arguments: [
            PlannerScopeCase(prompt: "Search Apple Notes for ORBIT", kind: .appleNotes),
            PlannerScopeCase(prompt: "Search my emails for ORBIT", kind: .appleMail),
            PlannerScopeCase(prompt: "Search my calendar events for ORBIT", kind: .calendar),
            PlannerScopeCase(prompt: "Search my reminders for ORBIT", kind: .reminders),
            PlannerScopeCase(prompt: "Search my contacts for ORBIT", kind: .contacts),
            PlannerScopeCase(prompt: "Search my browser history for ORBIT", kind: .browserProfile),
            PlannerScopeCase(prompt: "Search iMessage for ORBIT", kind: .messages),
            PlannerScopeCase(prompt: "Search my photos for ORBIT", kind: .photos),
            PlannerScopeCase(prompt: "Search my Apple Books for ORBIT", kind: .books),
            PlannerScopeCase(prompt: "Search my connected folder for ORBIT", kind: .folder),
            PlannerScopeCase(prompt: "Search this git repository for ORBIT", kind: .gitRepository),
        ]
    )
    func resolvesEveryConnector(item: PlannerScopeCase) {
        let plan = LocalQueryPlanner().plan(prompt: item.prompt, records: [], conversation: [])
        #expect(plan == .evidenceSearch(scope: [item.kind]))
    }

    @Test
    func userVisibleConnectionNameCanSelectScope() {
        let record = ConnectorRecord(
            kind: .folder,
            displayName: "Project Atlas",
            configuration: .init()
        )
        let plan = LocalQueryPlanner().plan(
            prompt: "What does Project Atlas say about ORBIT?",
            records: [record],
            conversation: []
        )
        #expect(plan == .evidenceSearch(scope: [.folder]))
    }

    @Test
    func connectorCapabilityIsSeparateFromContentSearch() {
        let plan = LocalQueryPlanner().plan(
            prompt: "Can you read my Apple Notes?",
            records: [],
            conversation: []
        )
        #expect(plan == .connectorCapability(scope: [.appleNotes]))
    }

    @Test
    func systemQuestionsComposeMultipleDomains() {
        let plan = LocalQueryPlanner().plan(
            prompt: "Show this Mac's RAM, processor, storage, and macOS specifications",
            records: [],
            conversation: []
        )
        #expect(plan == .system(SystemQueryPlan(
            domains: [.memory, .processor, .storage, .operatingSystem, .specifications],
            responseStyle: .synthesizedOverview
        )))
    }

    @Test
    func groundedShortFollowUpKeepsEvidencePath() {
        let conversation = [
            ChatMessage(
                role: .assistant,
                text: "The owner is Riya.",
                groundingSourceIDs: ["S1"]
            )
        ]
        let plan = LocalQueryPlanner().plan(
            prompt: "When was that decided?",
            records: [],
            conversation: conversation
        )
        #expect(plan == .evidenceSearch(scope: nil))
    }
}

struct PlannerScopeCase: Sendable, CustomTestStringConvertible {
    let prompt: String
    let kind: SourceConnectorKind

    var testDescription: String { prompt }
}
