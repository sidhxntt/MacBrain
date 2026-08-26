import Foundation

struct OnboardingPagePresentation: Equatable, Sendable {
    let title: String
    let explanation: String
    let symbolName: String
    let primaryActionTitle: String
    let accessibilitySummary: String
}

struct OnboardingReadySummary: Equatable, Sendable {
    let searchableKinds: Set<SourceConnectorKind>
    let emptyKinds: Set<SourceConnectorKind>
    let syncingKinds: Set<SourceConnectorKind>
    let permissionNeededKinds: Set<SourceConnectorKind>
    let failedKinds: Set<SourceConnectorKind>
    let optionalKinds: Set<SourceConnectorKind>
    let exampleQuestions: [String]
}

enum OnboardingPresentation {
    static func page(for step: OnboardingStep) -> OnboardingPagePresentation {
        switch step {
        case .introduction:
            OnboardingPagePresentation(
                title: "Your private, local Mac assistant",
                explanation: "MacBrain searches only the sources you choose and runs its assistant through the local model configured on this Mac. You stay in control of every connector and permission.",
                symbolName: "brain.head.profile",
                primaryActionTitle: "Continue",
                accessibilitySummary: "Introduction to MacBrain’s local processing and explicit connector consent."
            )
        case .localAI:
            OnboardingPagePresentation(
                title: "Prepare local AI",
                explanation: "MacBrain uses Ollama for conversational answers. Structured connector counts and read-only Mac facts remain available while model setup is incomplete.",
                symbolName: "cpu",
                primaryActionTitle: "Continue",
                accessibilitySummary: "Check Ollama and select the local chat and embedding models."
            )
        case .sources:
            OnboardingPagePresentation(
                title: "Connect what you choose",
                explanation: "Choose a connector to request its macOS permission and begin the first searchable sync immediately. MacBrain refreshes connected sources in the background.",
                symbolName: "link.badge.plus",
                primaryActionTitle: "Review readiness",
                accessibilitySummary: "Choose local sources and monitor their first verified searchable index."
            )
        case .ready:
            OnboardingPagePresentation(
                title: "MacBrain is ready",
                explanation: "Verified sources can be queried now. Sources still syncing or needing attention are listed separately, and you can change connector access later in Sources.",
                symbolName: "checkmark.seal.fill",
                primaryActionTitle: "Finish",
                accessibilitySummary: "Review searchable sources, attention states, and example questions."
            )
        }
    }

    static func readySummary(
        records: [ConnectorRecord],
        healthBySourceID: [UUID: ConnectorIndexHealth]
    ) -> OnboardingReadySummary {
        var searchable = Set<SourceConnectorKind>()
        var empty = Set<SourceConnectorKind>()
        var syncing = Set<SourceConnectorKind>()
        var permissionNeeded = Set<SourceConnectorKind>()
        var failed = Set<SourceConnectorKind>()

        for record in records {
            switch ConnectorPresentationState(
                record: record,
                health: healthBySourceID[record.id]
            ) {
            case .ready, .refreshing:
                searchable.insert(record.kind)
            case .empty:
                empty.insert(record.kind)
            case .connecting, .syncing:
                syncing.insert(record.kind)
            case .needsAuthorization:
                permissionNeeded.insert(record.kind)
            case .failed, .paused:
                failed.insert(record.kind)
            }
        }

        // A ready connection wins over another connection of the same kind.
        empty.subtract(searchable)
        syncing.subtract(searchable.union(empty))
        permissionNeeded.subtract(searchable.union(empty).union(syncing))
        failed.subtract(
            searchable.union(empty).union(syncing).union(permissionNeeded)
        )
        let connected = Set(records.map(\.kind))
        let optional = Set(SourceConnectorKind.userSelectableKinds).subtracting(connected)
        let exampleKinds = searchable.union(empty)
        let connectorExamples = SourceConnectorKind.allCases.compactMap { kind in
            exampleKinds.contains(kind) ? exampleQuestion(for: kind) : nil
        }
        let systemExamples = [
            "How much memory is free right now?",
            "How much storage is available?",
            "Show this Mac’s specifications.",
        ]

        return OnboardingReadySummary(
            searchableKinds: searchable,
            emptyKinds: empty,
            syncingKinds: syncing,
            permissionNeededKinds: permissionNeeded,
            failedKinds: failed,
            optionalKinds: optional,
            exampleQuestions: Array(connectorExamples.prefix(3)) + systemExamples
        )
    }

    private static func exampleQuestion(for kind: SourceConnectorKind) -> String {
        switch kind {
        case .appleNotes: "How many notes do I have?"
        case .appleMail: "What is my newest email?"
        case .calendar: "What is my next calendar event?"
        case .reminders: "What is my first due reminder?"
        case .contacts: "Find the contact I asked about."
        case .browserProfile: "Find the page I visited about my project."
        case .messages: "What is my newest message?"
        case .photos: "What is my newest photo?"
        case .books: "How many books do I have?"
        case .folder: "Summarize the project handoff in my folder."
        case .gitRepository: "What changed in this repository?"
        }
    }
}
