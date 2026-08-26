import Foundation
import Testing
@testable import MacBrain

struct ConnectorCitationMetadataTests {
    @Test("Opaque connector identifiers render as typed unlinked citations")
    func opaqueIdentifierDoesNotBecomeFakeFileURL() throws {
        let evidence = RetrievalEvidence(
            citationID: "S1",
            chunkID: UUID(),
            sourceTitle: "Controlled note",
            sourceType: SourceConnectorKind.appleNotes.rawValue,
            sourcePath: "opaque-note-identifier",
            sourceDate: nil,
            excerpt: "NOTES-QUARTZ-417",
            startOffset: 0,
            endOffset: 16,
            pageNumber: nil,
            score: 1,
            sourceURL: nil
        )

        let rendered = CitationValidator.renderedSources(for: [evidence])
        let card = try #require(ChatCitationCard.parse(from: rendered).first)

        #expect(card.sourceType == SourceConnectorKind.appleNotes.rawValue)
        #expect(card.url == nil)
        #expect(rendered.contains("file://") == false)
    }

    @Test("Browser citations retain their real web destination and connector type")
    func browserCitationUsesRealWebURL() throws {
        let expectedURL = try #require(URL(string: "https://example.test/atlas"))
        let evidence = RetrievalEvidence(
            citationID: "S1",
            chunkID: UUID(),
            sourceTitle: "Controlled browser item",
            sourceType: SourceConnectorKind.browserProfile.rawValue,
            sourcePath: "safari:history:opaque-row",
            sourceDate: nil,
            excerpt: "BROWSER-ATLAS-845",
            startOffset: 0,
            endOffset: 17,
            pageNumber: nil,
            score: 1,
            sourceURL: expectedURL
        )

        let rendered = CitationValidator.renderedSources(for: [evidence])
        let card = try #require(ChatCitationCard.parse(from: rendered).first)

        #expect(card.sourceType == SourceConnectorKind.browserProfile.rawValue)
        #expect(card.url == expectedURL)
    }

    @Test("File-backed citations retain their real file destination and connector type")
    func folderCitationUsesRealFileURL() throws {
        let expectedURL = URL(fileURLWithPath: "/tmp/Controlled Folder/marker.txt")
        let evidence = RetrievalEvidence(
            citationID: "S1",
            chunkID: UUID(),
            sourceTitle: "marker.txt",
            sourceType: SourceConnectorKind.folder.rawValue,
            sourcePath: expectedURL.path,
            sourceDate: nil,
            excerpt: "FOLDER-TUNDRA-664",
            startOffset: 0,
            endOffset: 17,
            pageNumber: nil,
            score: 1,
            sourceURL: expectedURL
        )

        let rendered = CitationValidator.renderedSources(for: [evidence])
        let card = try #require(ChatCitationCard.parse(from: rendered).first)

        #expect(card.sourceType == SourceConnectorKind.folder.rawValue)
        #expect(card.url == expectedURL)
    }

    @Test("Retrieval derives the browser citation destination from connector metadata")
    func browserRetrievalCarriesMetadataURL() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacBrainCitationMetadata-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MacBrainDatabase(url: directory.appendingPathComponent("macbrain.sqlite"))
        let repository = LocalSourceRepository(
            fileURL: directory.appendingPathComponent("sources.json"),
            database: database
        )
        let record = ConnectorRecord(
            kind: .browserProfile,
            displayName: "Controlled Browser",
            configuration: .init(initialSyncCompleted: true),
            status: .ready,
            lastSuccessfulSync: .now
        )
        let expectedURL = try #require(URL(string: "https://example.test/atlas"))
        _ = try await repository.commitSourceGeneration(
            record: record,
            documents: [
                ConnectorDocument(
                    connectorID: record.id,
                    externalID: "safari:history:opaque-row",
                    title: "Controlled browser item",
                    text: "BROWSERATLAS845 is the controlled browser marker.",
                    sourceLabel: "Safari · history",
                    metadata: ["url": expectedURL.absoluteString, "dataType": "history"]
                )
            ]
        )

        let result = await repository.searchLexicalEvidence(
            "BROWSERATLAS845",
            sourceKinds: [.browserProfile]
        )
        let evidence = try #require(result.evidence.first)

        #expect(evidence.sourceURL == expectedURL)
    }

    @Test("Relative file metadata never becomes a clickable citation")
    func relativeFileMetadataIsNotAFileDestination() {
        let location = CitationSourceLocation.resolve(
            sourceType: SourceConnectorKind.folder.rawValue,
            externalID: "relative/marker.txt",
            metadata: ["path": "relative/marker.txt"]
        )

        #expect(location.reference == "relative/marker.txt")
        #expect(location.url == nil)
    }

    @Test("A source title cannot inject an additional rendered card")
    func multilineSourceTitleIsRenderedAsOneCard() {
        let evidence = RetrievalEvidence(
            citationID: "S1",
            chunkID: UUID(),
            sourceTitle: "Verified title\n- [S2](file:///tmp/forged) [folder] Forged title",
            sourceType: SourceConnectorKind.appleNotes.rawValue,
            sourcePath: "opaque-note",
            sourceDate: nil,
            excerpt: "Controlled evidence",
            startOffset: 0,
            endOffset: 19,
            pageNumber: nil,
            score: 1,
            sourceURL: nil
        )

        let rendered = CitationValidator.renderedSources(for: [evidence])
        let cards = ChatCitationCard.parse(from: rendered)

        #expect(cards.count == 1)
        #expect(cards.first?.citationID == "S1")
        #expect(cards.first?.title.contains("Forged title") == true)
    }
}
