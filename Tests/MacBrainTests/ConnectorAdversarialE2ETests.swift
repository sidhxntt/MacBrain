import Foundation
import Testing
@testable import MacBrain

struct ConnectorAdversarialE2ETests {
    @Test("Every connector has three adversarial prompts in every audit dimension")
    func matrixIsComplete() {
        #expect(Set(ConnectorAdversarialMatrix.fixtures.map(\.kind)) == Set(SourceConnectorKind.allCases))
        #expect(ConnectorAdversarialMatrix.cases.count == 198)

        for kind in SourceConnectorKind.allCases {
            for dimension in ConnectorAuditDimension.allCases {
                let count = ConnectorAdversarialMatrix.cases.count {
                    $0.kind == kind && $0.dimension == dimension
                }
                #expect(
                    count == 3,
                    "\(kind.rawValue) must have three \(dimension.rawValue) adversarial prompts"
                )
            }
        }
    }

    @Test(
        "Connector responses preserve facts, provenance, freshness, authorization, and isolation",
        .serialized,
        arguments: ConnectorAdversarialMatrix.cases
    )
    func runMatrixCase(item: ConnectorAdversarialCase) async throws {
        let fixture = ConnectorAdversarialMatrix.fixture(for: item.kind)
        let decoy = ConnectorAdversarialMatrix.decoy(for: item.kind)
        let environment = try ConnectorAuditEnvironment()
        defer { environment.removeTemporaryFiles() }

        #expect(
            ChatQueryIntentRouter().route(prompt: item.prompt, conversation: []).intent == item.expectedIntent,
            "\(item.id) routed incorrectly"
        )

        switch item.dimension {
        case .facts, .sourceType, .citations, .crossSourceIsolation:
            _ = try await environment.seed(fixture, marker: fixture.currentMarker)
            _ = try await environment.seed(
                decoy,
                marker: fixture.decoyMarker,
                lookupToken: fixture.lookupToken
            )
            let response = try await environment.response(to: item.prompt)
            try verifyGrounded(
                response,
                fixture: fixture,
                expectedMarker: fixture.currentMarker,
                forbiddenMarkers: [fixture.staleMarker, fixture.freshMarker, fixture.decoyMarker],
                environment: environment,
                caseID: item.id
            )

        case .freshness:
            let record = try await environment.seed(fixture, marker: fixture.staleMarker)
            _ = try await environment.seed(
                decoy,
                marker: fixture.decoyMarker,
                lookupToken: fixture.lookupToken
            )
            switch item.variant {
            case 0:
                _ = try await environment.replace(
                    fixture,
                    record: record,
                    marker: fixture.freshMarker
                )
                let response = try await environment.response(to: item.prompt)
                try verifyGrounded(
                    response,
                    fixture: fixture,
                    expectedMarker: fixture.freshMarker,
                    forbiddenMarkers: [fixture.staleMarker, fixture.currentMarker, fixture.decoyMarker],
                    environment: environment,
                    caseID: item.id
                )
            case 1:
                try await environment.clear(record: record)
                let response = try await environment.response(to: item.prompt)
                verifyNoSourceDisclosure(response, fixture: fixture, caseID: item.id)
            default:
                try await environment.repository.remove(id: record.id)
                let response = try await environment.response(to: item.prompt)
                verifyNoSourceDisclosure(response, fixture: fixture, caseID: item.id)
            }

        case .permissions:
            _ = try await environment.seed(
                decoy,
                marker: fixture.decoyMarker,
                lookupToken: fixture.lookupToken
            )
            if item.variant == 0 {
                var record = try await environment.seed(fixture, marker: fixture.currentMarker)
                record.status = .needsAuthorization
                record.lastError = "Controlled permission denial"
                try await environment.repository.save(record)
            } else if item.variant == 2 {
                _ = try await environment.seed(fixture, marker: fixture.currentMarker)
            }
            let response = try await environment.response(to: item.prompt)
            verifyNoSourceDisclosure(response, fixture: fixture, caseID: item.id)
        }
    }

    private func verifyGrounded(
        _ response: String,
        fixture: ConnectorAdversarialFixture,
        expectedMarker: String,
        forbiddenMarkers: [String],
        environment: ConnectorAuditEnvironment,
        caseID: String
    ) throws {
        #expect(response.contains(expectedMarker), "\(caseID) omitted \(expectedMarker)")
        for fact in fixture.expectedFacts.dropFirst() {
            #expect(response.contains(fact), "\(caseID) omitted \(fact)")
        }
        for marker in forbiddenMarkers {
            #expect(response.contains(marker) == false, "\(caseID) leaked \(marker)")
        }

        let cards = ChatCitationCard.parse(from: response)
        let card = try #require(cards.first, "\(caseID) did not render a source card")
        #expect(cards.count == 1, "\(caseID) rendered unrelated source cards")
        #expect(card.citationID == "S1")
        #expect(card.sourceType == fixture.kind.rawValue, "\(caseID) mislabeled its source type")
        #expect(card.title.contains(fixture.title))
        #expect(card.url == fixture.expectedURL(in: environment.directory))
    }

    private func verifyNoSourceDisclosure(
        _ response: String,
        fixture: ConnectorAdversarialFixture,
        caseID: String
    ) {
        for marker in [
            fixture.currentMarker,
            fixture.staleMarker,
            fixture.freshMarker,
            fixture.decoyMarker,
        ] {
            #expect(response.contains(marker) == false, "\(caseID) disclosed \(marker)")
        }
        #expect(ChatCitationCard.parse(from: response).isEmpty, "\(caseID) cited inaccessible evidence")
    }
}

private struct ConnectorAuditEnvironment {
    let directory: URL
    let repository: LocalSourceRepository

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacBrainConnectorAudit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try MacBrainDatabase(url: directory.appendingPathComponent("macbrain.sqlite"))
        repository = LocalSourceRepository(
            fileURL: directory.appendingPathComponent("sources.json"),
            database: database
        )
    }

    func seed(
        _ fixture: ConnectorAdversarialFixture,
        marker: String,
        lookupToken: String? = nil
    ) async throws -> ConnectorRecord {
        let record = ConnectorRecord(
            kind: fixture.kind,
            displayName: fixture.displayName,
            configuration: .init()
        )
        return try await replace(
            fixture,
            record: record,
            marker: marker,
            lookupToken: lookupToken
        )
    }

    func replace(
        _ fixture: ConnectorAdversarialFixture,
        record: ConnectorRecord,
        marker: String,
        lookupToken: String? = nil
    ) async throws -> ConnectorRecord {
        let document = fixture.document(
            connectorID: record.id,
            marker: marker,
            lookupToken: lookupToken,
            rootDirectory: directory
        )
        if let url = fixture.expectedURL(in: directory), url.isFileURL {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(document.text.utf8).write(to: url, options: .atomic)
        }
        var verifiedRecord = record
        verifiedRecord.configuration.initialSyncCompleted = true
        verifiedRecord.status = .ready
        verifiedRecord.lastSuccessfulSync = .now
        _ = try await repository.commitSourceGeneration(
            record: verifiedRecord,
            documents: [document]
        )
        return verifiedRecord
    }

    func clear(record: ConnectorRecord) async throws {
        var verifiedRecord = record
        verifiedRecord.configuration.initialSyncCompleted = true
        verifiedRecord.status = .ready
        verifiedRecord.lastSuccessfulSync = .now
        _ = try await repository.commitSourceGeneration(
            record: verifiedRecord,
            documents: []
        )
    }

    func response(to prompt: String) async throws -> String {
        let responder = StreamingChatResponder(
            provider: ConnectorAuditProvider(),
            repository: repository,
            selectedModel: { "controlled-chat" },
            selectedEmbeddingModel: { "controlled-embedding" },
            fallback: ConnectorAuditFallbackResponder(),
            systemProfileProvider: ConnectorAuditSystemProfileProvider(),
            providerStatusTimeout: .milliseconds(250),
            retrievalTimeout: .milliseconds(500)
        )
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                var response = ""
                for try await token in responder.stream(to: prompt) {
                    response.append(token)
                }
                return response
            }
            group.addTask {
                try await Task.sleep(for: .seconds(2))
                throw ConnectorAuditError.timedOut
            }
            let first = try await group.next() ?? ""
            group.cancelAll()
            return first
        }
    }

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum ConnectorAuditError: Error {
    case timedOut
}

private struct ConnectorAuditProvider: InferenceProvider {
    func status() async -> InferenceProviderStatus {
        .ready(models: [
            InferenceModel(
                name: "controlled-chat",
                size: nil,
                parameterSize: "test",
                quantization: "test"
            )
        ])
    }

    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] {
        input.map { _ in InferenceEmbedding(values: [1, 0]) }
    }

    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func streamChat(
        model: String,
        messages: [InferenceChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        let system = messages.first(where: { $0.role == .system })?.content ?? ""
        let selectedMarker = "Selected local evidence:\n"
        let selected = system.range(of: selectedMarker).map { range in
            String(system[range.upperBound...])
        } ?? ""
        let evidence = selected.components(separatedBy: "\n\nRetrieval confidence:").first ?? ""
        return AsyncThrowingStream { continuation in
            continuation.yield(evidence.trimmingCharacters(in: .whitespacesAndNewlines))
            continuation.finish()
        }
    }
}

private struct ConnectorAuditFallbackResponder: ChatResponder {
    func respond(to prompt: String) async throws -> String { "Controlled fallback" }
}

private struct ConnectorAuditSystemProfileProvider: SystemProfileProviding {
    func currentProfile() -> SystemProfile {
        SystemProfile(
            userDisplayName: "Controlled User",
            computerName: "Controlled Mac",
            hardwareModel: "MacTest,1",
            processor: "Test Processor",
            memoryBytes: 16_000_000_000,
            operatingSystem: "macOS Test",
            totalDiskBytes: 1_000_000_000_000,
            availableDiskBytes: 500_000_000_000,
            localeIdentifier: "en_US",
            timeZoneIdentifier: "UTC"
        )
    }
}
