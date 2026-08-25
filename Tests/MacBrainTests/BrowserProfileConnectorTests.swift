@testable import MacBrain
import Foundation
import XCTest

final class BrowserProfileConnectorTests: XCTestCase {
    func testChromiumProfileIndexesBookmarksReadingListHistoryAndDownloads() async throws {
        let profile = try makeTemporaryDirectory()
        let bookmarks = """
        {
          "roots": {
            "bookmark_bar": { "children": [{ "type": "url", "id": "bookmark-1", "name": "MacBrain", "url": "https://macbrain.local" }] },
            "reading_list": { "children": [{ "type": "url", "id": "reading-1", "name": "Read later", "url": "https://example.com/later" }] }
          }
        }
        """
        try Data(bookmarks.utf8).write(to: profile.appendingPathComponent("Bookmarks"))
        try Data().write(to: profile.appendingPathComponent("History"))
        let record = ConnectorRecord(
            kind: .browserProfile,
            displayName: "Chrome · Default",
            configuration: SourceConnectorConfiguration(
                localPath: profile.path,
                browserKind: .chrome,
                browserProfileName: "Default"
            )
        )

        let documents = try await BrowserProfileConnector(
            reader: ChromiumFixtureReader(),
            tabProvider: EmptyBrowserTabProvider()
        ).sync(record: record)

        XCTAssertEqual(Set(documents.map { $0.metadata["dataType"] }), ["bookmark", "readingList", "history", "download"])
        XCTAssertTrue(documents.allSatisfy { $0.metadata["browser"] == "Chrome" })
        XCTAssertTrue(documents.contains { $0.metadata["url"] == "https://macbrain.local" })
        XCTAssertTrue(documents.contains { $0.metadata["url"] == "https://example.com/download.zip" })
    }

    func testFirefoxProfileIndexesPlacesBookmarksHistoryDownloadsAndReadingList() async throws {
        let profile = try makeTemporaryDirectory()
        try Data().write(to: profile.appendingPathComponent("places.sqlite"))
        let record = ConnectorRecord(
            kind: .browserProfile,
            displayName: "Firefox · Work",
            configuration: SourceConnectorConfiguration(
                localPath: profile.path,
                browserKind: .firefox,
                browserProfileName: "Work"
            )
        )

        let documents = try await BrowserProfileConnector(
            reader: FirefoxFixtureReader(),
            tabProvider: EmptyBrowserTabProvider()
        ).sync(record: record)

        XCTAssertEqual(Set(documents.map { $0.metadata["dataType"] }), ["bookmark", "readingList", "history", "download"])
        XCTAssertTrue(documents.allSatisfy { $0.metadata["browser"] == "Firefox" })
        XCTAssertTrue(documents.contains { $0.metadata["url"] == "https://mozilla.org" })
    }

    func testOpenTabsAppendWithoutBlockingStoredProfileDocuments() async throws {
        let profile = try makeTemporaryDirectory()
        let record = ConnectorRecord(
            kind: .browserProfile,
            displayName: "Arc · Default",
            configuration: SourceConnectorConfiguration(
                localPath: profile.path,
                browserKind: .arc,
                browserProfileName: "Default"
            )
        )
        let connector = BrowserProfileConnector(
            reader: EmptyBrowserReader(),
            tabProvider: FixedBrowserTabProvider(tabs: [
                BrowserTabSnapshot(title: "MacBrain tab", url: "https://macbrain.local/tab")
            ])
        )

        let documents = try await connector.sync(record: record)

        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents[0].metadata["dataType"], "openTab")
        XCTAssertEqual(documents[0].metadata["browser"], "Arc")
        XCTAssertEqual(documents[0].metadata["url"], "https://macbrain.local/tab")
    }

    func testSafariProfileIndexesBookmarksAndReadingList() async throws {
        let profile = try makeTemporaryDirectory()
        let bookmarks: [String: Any] = [
            "Children": [
                ["Title": "Favorites", "Children": [["Title": "MacBrain", "URLString": "https://macbrain.local"]]],
                ["Title": "Reading List", "Children": [["Title": "Read later", "URLString": "https://example.com/later"]]]
            ]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: bookmarks, format: .binary, options: 0)
        try data.write(to: profile.appendingPathComponent("Bookmarks.plist"))
        let record = ConnectorRecord(
            kind: .browserProfile,
            displayName: "Safari · Safari",
            configuration: SourceConnectorConfiguration(localPath: profile.path, browserKind: .safari, browserProfileName: "Safari")
        )

        let documents = try await BrowserProfileConnector(tabProvider: EmptyBrowserTabProvider()).sync(record: record)

        XCTAssertEqual(Set(documents.map { $0.metadata["dataType"] }), ["bookmark", "readingList"])
        XCTAssertTrue(documents.allSatisfy { $0.metadata["browser"] == "Safari" })
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct ChromiumFixtureReader: LocalSQLiteReading {
    func read(databaseURL: URL, query: String) async throws -> String {
        if query.contains("downloads") {
            return "download-1\u{1F}https://example.com/download.zip\u{1F}download.zip\u{1F}2026-08-25 00:00:00\u{1F}42\n"
        }
        return "history-1\u{1F}https://example.com/history\u{1F}Visited page\u{1F}2026-08-25 00:00:00\u{1F}3\n"
    }
}

private struct FirefoxFixtureReader: LocalSQLiteReading {
    func read(databaseURL: URL, query: String) async throws -> String {
        if query.contains("moz_bookmarks") {
            return "bookmark-1\u{1F}https://mozilla.org\u{1F}Mozilla\u{1F}Bookmarks Menu\u{1F}2026-08-25 00:00:00\nreading-1\u{1F}https://example.com/read\u{1F}Read later\u{1F}Reading List\u{1F}2026-08-25 00:00:00\n"
        }
        if query.contains("moz_annos") {
            return "download-1\u{1F}https://example.com/firefox-download\u{1F}report.pdf\u{1F}2026-08-25 00:00:00\u{1F}12\n"
        }
        return "history-1\u{1F}https://example.com/firefox-history\u{1F}Firefox history\u{1F}2026-08-25 00:00:00\u{1F}4\n"
    }
}

private struct EmptyBrowserReader: LocalSQLiteReading {
    func read(databaseURL: URL, query: String) async throws -> String { "" }
}

private struct EmptyBrowserTabProvider: BrowserTabSnapshotProviding {
    func snapshots(for browser: BrowserKind) async -> [BrowserTabSnapshot] { [] }
}

private struct FixedBrowserTabProvider: BrowserTabSnapshotProviding {
    let tabs: [BrowserTabSnapshot]
    func snapshots(for browser: BrowserKind) async -> [BrowserTabSnapshot] { tabs }
}
