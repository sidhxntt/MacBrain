import Foundation
import XCTest
@testable import MacBrain

final class LocalFileIndexerTests: XCTestCase {
    func testSecondScanUsesFingerprintsAndReturnsOnlyChangedDocuments() throws {
        let root = try makeIndexerDirectory()
        let file = root.appendingPathComponent("brief.md")
        try Data("# Brief\nInitial evidence".utf8).write(to: file)
        let connectorID = UUID()

        let initial = try LocalFileIndexer.scan(
            rootURL: root,
            connectorID: connectorID,
            sourceLabel: "Folder: Work"
        )
        let unchanged = try LocalFileIndexer.scan(
            rootURL: root,
            connectorID: connectorID,
            sourceLabel: "Folder: Work",
            knownFingerprints: initial.fingerprints
        )

        XCTAssertEqual(initial.changedDocuments.count, 1)
        XCTAssertTrue(unchanged.changedDocuments.isEmpty)
        XCTAssertEqual(unchanged.presentExternalIDs, initial.presentExternalIDs)

        try Data("# Brief\nRevised evidence".utf8).write(to: file)
        let changed = try LocalFileIndexer.scan(
            rootURL: root,
            connectorID: connectorID,
            sourceLabel: "Folder: Work",
            knownFingerprints: initial.fingerprints
        )
        XCTAssertEqual(changed.changedDocuments.count, 1)
        XCTAssertTrue(changed.changedDocuments[0].text.contains("Revised"))
    }

    func testUserExcludesRemoveMatchingDescendantsWhileKeepingHiddenFiles() throws {
        let root = try makeIndexerDirectory()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Private", isDirectory: true), withIntermediateDirectories: true)
        try Data("Included".utf8).write(to: root.appendingPathComponent(".env"))
        try Data("Excluded".utf8).write(to: root.appendingPathComponent("Private/notes.md"))

        let result = try LocalFileIndexer.scan(
            rootURL: root,
            connectorID: UUID(),
            sourceLabel: "Folder: Work",
            excludedRelativePaths: ["Private"]
        )

        XCTAssertEqual(result.changedDocuments.map { $0.metadata["relativePath"] }, [".env"])
    }

    private func makeIndexerDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalFileIndexerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
