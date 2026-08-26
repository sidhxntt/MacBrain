import Foundation
import SwiftUI
import Testing
@testable import MacBrain

struct OnboardingPresentationTests {
    @Test(arguments: OnboardingStep.allCases)
    func everyPageHasConciseAccessibleActions(step: OnboardingStep) {
        let page = OnboardingPresentation.page(for: step)

        #expect(!page.title.isEmpty)
        #expect(!page.explanation.isEmpty)
        #expect(!page.symbolName.isEmpty)
        #expect(!page.primaryActionTitle.isEmpty)
        #expect(!page.accessibilitySummary.isEmpty)
        #expect(!page.explanation.localizedCaseInsensitiveContains("cloud"))
        #expect(!page.explanation.localizedCaseInsensitiveContains("guaranteed"))
        #expect(!page.explanation.localizedCaseInsensitiveContains("all data"))
    }

    @Test
    func readySummaryUsesOnlyVerifiedConnectorHealthForExamples() {
        let notes = record(kind: .appleNotes, status: .ready)
        let calendar = record(kind: .calendar, status: .ready)
        let mail = record(kind: .appleMail, status: .ready)
        let health: [UUID: ConnectorIndexHealth] = [
            notes.id: verifiedHealth(for: notes, count: 3),
            calendar.id: verifiedHealth(for: calendar, count: 0),
        ]

        let summary = OnboardingPresentation.readySummary(
            records: [notes, calendar, mail],
            healthBySourceID: health
        )

        #expect(summary.searchableKinds == [.appleNotes])
        #expect(summary.emptyKinds == [.calendar])
        #expect(summary.syncingKinds == [.appleMail])
        #expect(summary.exampleQuestions.contains("How many notes do I have?"))
        #expect(summary.exampleQuestions.contains { $0.localizedCaseInsensitiveContains("mail") } == false)
        #expect(summary.exampleQuestions.contains("How much memory is free right now?"))
        #expect(summary.exampleQuestions.contains("How much storage is available?"))
    }

    @Test
    func permissionFailureAndOptionalSourcesRemainDistinct() {
        let messages = record(kind: .messages, status: .needsAuthorization)
        let photos = record(kind: .photos, status: .failed)

        let summary = OnboardingPresentation.readySummary(
            records: [messages, photos],
            healthBySourceID: [:]
        )

        #expect(summary.permissionNeededKinds == [.messages])
        #expect(summary.failedKinds == [.photos])
        #expect(summary.optionalKinds.contains(.appleNotes))
        #expect(summary.optionalKinds.contains(.appleMail))
        #expect(summary.exampleQuestions.contains { $0.localizedCaseInsensitiveContains("messages") } == false)
        #expect(summary.exampleQuestions.contains { $0.localizedCaseInsensitiveContains("photos") } == false)
    }

    @MainActor
    @Test
    func nativePagesCanBeConstructedWithSharedStores() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "macbrain-onboarding-view-tests-" + UUID().uuidString,
            isDirectory: true
        )
        let sourceLibrary = SourceLibraryStore(
            repository: LocalSourceRepository(
                fileURL: directory.appendingPathComponent("sources.json")
            ),
            database: nil
        )
        let inferenceStore = InferenceStore(
            provider: OnboardingPresentationProvider(),
            preferences: UserDefaults(suiteName: UUID().uuidString)!
        )
        let onboardingStore = OnboardingStore(
            defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        let summary = OnboardingPresentation.readySummary(
            records: [],
            healthBySourceID: [:]
        )

        _ = OnboardingIntroductionView()
        _ = OnboardingSourcesView(store: sourceLibrary)
        _ = OnboardingReadyView(summary: summary)
        _ = MacBrainOnboardingView(
            store: onboardingStore,
            sourceLibrary: sourceLibrary,
            inferenceStore: inferenceStore
        )
    }

    private func record(
        kind: SourceConnectorKind,
        status: ConnectorStatus
    ) -> ConnectorRecord {
        ConnectorRecord(
            kind: kind,
            displayName: kind.displayName,
            configuration: .init(initialSyncCompleted: status == .ready),
            status: status,
            lastSuccessfulSync: status == .ready ? .now : nil
        )
    }

    private func verifiedHealth(
        for record: ConnectorRecord,
        count: Int
    ) -> ConnectorIndexHealth {
        ConnectorIndexHealth(
            sourceID: record.id,
            documentCount: count,
            chunkCount: count,
            contentRevision: "revision-\(count)",
            initialSyncCompleted: true,
            lastSuccessfulSync: .now,
            lastVerifiedAt: .now
        )
    }
}

private struct OnboardingPresentationProvider: InferenceProvider {
    func status() async -> InferenceProviderStatus { .runtimeMissing }
    func streamChat(
        model: String,
        messages: [InferenceChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] { [] }
    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
