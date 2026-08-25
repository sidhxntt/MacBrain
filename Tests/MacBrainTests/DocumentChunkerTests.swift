import XCTest
@testable import MacBrain

final class DocumentChunkerTests: XCTestCase {
    func testSplitsTextWithStableOverlappingChunks() {
        let sourceID = UUID()
        let document = StoredDocument(
            sourceID: sourceID,
            externalID: "work/brief.md",
            title: "Brief",
            text: "one two three four five six seven eight nine ten",
            sourceLabel: "Work"
        )

        let first = DocumentChunker(maximumUTF16Length: 18, overlapUTF16Length: 4).chunks(for: document)
        let second = DocumentChunker(maximumUTF16Length: 18, overlapUTF16Length: 4).chunks(for: document)

        XCTAssertGreaterThan(first.count, 1)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.map(\.startOffset), [0, 14, 28, 42])
        XCTAssertEqual(first.dropFirst().first?.text.prefix(4), first.first?.text.suffix(4))
    }

    func testTracksMarkdownLineRangeAndNearestHeading() {
        let document = StoredDocument(
            sourceID: UUID(),
            externalID: "work/brief.md",
            title: "Brief",
            text: "# Launch\nAlpha beta\n## Risks\nGamma delta\n",
            sourceLabel: "Work",
            metadata: ["format": "md"]
        )

        let chunks = DocumentChunker(maximumUTF16Length: 16, overlapUTF16Length: 0).chunks(for: document)

        XCTAssertEqual(chunks.first?.lineStart, 1)
        XCTAssertEqual(chunks.first?.lineEnd, 2)
        XCTAssertEqual(chunks.last?.lineStart, 4)
        XCTAssertEqual(chunks.last?.lineEnd, 4)
    }

    func testCarriesPDFPageNumberToEveryChunk() {
        let document = StoredDocument(
            sourceID: UUID(),
            externalID: "work/report.pdf#page-7",
            title: "Report · page 7",
            text: "This page contains enough content to split into multiple citation chunks.",
            sourceLabel: "Work",
            metadata: ["format": "pdf", "pageNumber": "7"]
        )

        let chunks = DocumentChunker(maximumUTF16Length: 20, overlapUTF16Length: 4).chunks(for: document)

        XCTAssertTrue(chunks.allSatisfy { $0.pageNumber == 7 })
    }
}
