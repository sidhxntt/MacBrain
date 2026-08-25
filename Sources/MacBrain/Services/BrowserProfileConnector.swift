import Foundation

struct BrowserProfileConnector: SourceConnector {
    let kind: SourceConnectorKind = .browserProfile
    let reader: any LocalSQLiteReading
    let tabProvider: any BrowserTabSnapshotProviding

    init(
        reader: any LocalSQLiteReading = LocalSQLiteReader(),
        tabProvider: any BrowserTabSnapshotProviding = BrowserTabSnapshotProvider()
    ) {
        self.reader = reader
        self.tabProvider = tabProvider
    }

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        guard let browser = record.configuration.browserKind else {
            throw ConnectorError.invalidConfiguration("Choose a browser and profile folder before syncing.")
        }
        let access = try SecurityScopedLocalAccess(configuration: record.configuration)
        defer { access.stop() }
        guard FileManager.default.fileExists(atPath: access.url.path) else {
            throw ConnectorError.sourceUnavailable("The selected browser profile is no longer available.")
        }

        var documents: [ConnectorDocument]
        switch browser.engine {
        case .chromium:
            documents = await chromiumDocuments(browser: browser, profileURL: access.url, record: record)
        case .firefox:
            documents = await firefoxDocuments(browser: browser, profileURL: access.url, record: record)
        case .safari:
            documents = safariDocuments(browser: browser, profileURL: access.url, record: record)
        case .webKit, .unknown:
            throw ConnectorError.sourceUnavailable("\(browser.displayName) does not expose a supported local profile format yet.")
        }
        documents += await openTabDocuments(browser: browser, record: record)
        return documents
    }

    private func chromiumDocuments(
        browser: BrowserKind,
        profileURL: URL,
        record: ConnectorRecord
    ) async -> [ConnectorDocument] {
        var documents = bookmarkDocuments(
            browser: browser,
            profileURL: profileURL,
            record: record
        )
        let historyURL = profileURL.appendingPathComponent("History")
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return documents }

        if let output = try? await reader.read(databaseURL: historyURL, query: chromiumHistoryQuery) {
            documents += historyDocuments(output, browser: browser, record: record)
        }
        if let output = try? await reader.read(databaseURL: historyURL, query: chromiumDownloadsQuery) {
            documents += downloadDocuments(output, browser: browser, record: record)
        }
        return documents
    }

    private func firefoxDocuments(browser: BrowserKind, profileURL: URL, record: ConnectorRecord) async -> [ConnectorDocument] {
        let databaseURL = profileURL.appendingPathComponent("places.sqlite")
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }

        var documents: [ConnectorDocument] = []
        if let output = try? await reader.read(databaseURL: databaseURL, query: firefoxBookmarksQuery) {
            documents += firefoxBookmarkDocuments(output, browser: browser, record: record)
        }
        if let output = try? await reader.read(databaseURL: databaseURL, query: firefoxHistoryQuery) {
            documents += historyDocuments(output, browser: browser, record: record)
        }
        if let output = try? await reader.read(databaseURL: databaseURL, query: firefoxDownloadsQuery) {
            documents += downloadDocuments(output, browser: browser, record: record)
        }
        return documents
    }

    private func bookmarkDocuments(
        browser: BrowserKind,
        profileURL: URL,
        record: ConnectorRecord
    ) -> [ConnectorDocument] {
        let url = profileURL.appendingPathComponent("Bookmarks")
        guard
            let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let roots = root["roots"] as? [String: Any]
        else { return [] }

        var documents: [ConnectorDocument] = []
        for (rootName, rootNode) in roots {
            guard let node = rootNode as? [String: Any] else { continue }
            walkBookmarkNode(
                node,
                browser: browser,
                record: record,
                path: [rootName],
                isReadingList: rootName.localizedCaseInsensitiveContains("reading"),
                documents: &documents
            )
        }
        return documents
    }

    private func walkBookmarkNode(
        _ node: [String: Any],
        browser: BrowserKind,
        record: ConnectorRecord,
        path: [String],
        isReadingList: Bool,
        documents: inout [ConnectorDocument]
    ) {
        let nodeTitle = node["name"] as? String ?? ""
        let nodeType = node["type"] as? String ?? ""
        let nextPath = nodeType == "folder" && !nodeTitle.isEmpty ? path + [nodeTitle] : path
        let readingList = isReadingList || nextPath.joined(separator: "/").localizedCaseInsensitiveContains("reading")

        if nodeType == "url", let url = node["url"] as? String, !url.isEmpty {
            let dataType = readingList ? "readingList" : "bookmark"
            documents.append(document(
                record: record,
                browser: browser,
                dataType: dataType,
                externalID: "\(dataType):\(node["id"] as? String ?? url)",
                title: nodeTitle.isEmpty ? url : nodeTitle,
                text: "URL: \(url)\nFolder: \(path.joined(separator: " / "))",
                url: url,
                timestamp: node["date_added"] as? String,
                extraMetadata: ["folder": path.joined(separator: " / ")]
            ))
        }

        for child in node["children"] as? [[String: Any]] ?? [] {
            walkBookmarkNode(
                child,
                browser: browser,
                record: record,
                path: nextPath,
                isReadingList: readingList,
                documents: &documents
            )
        }
    }

    private func firefoxBookmarkDocuments(_ output: String, browser: BrowserKind, record: ConnectorRecord) -> [ConnectorDocument] {
        rows(output).compactMap { row in
            guard row.count >= 5 else { return nil }
            let isReadingList = row[3].localizedCaseInsensitiveContains("reading")
            return document(
                record: record,
                browser: browser,
                dataType: isReadingList ? "readingList" : "bookmark",
                externalID: "bookmark:\(row[0])",
                title: row[2].isEmpty ? row[1] : row[2],
                text: "URL: \(row[1])\nFolder: \(row[3])",
                url: row[1],
                timestamp: row[4],
                extraMetadata: ["folder": row[3]]
            )
        }
    }

    private func safariDocuments(browser: BrowserKind, profileURL: URL, record: ConnectorRecord) -> [ConnectorDocument] {
        let bookmarksURL = profileURL.appendingPathComponent("Bookmarks.plist")
        guard
            let data = try? Data(contentsOf: bookmarksURL),
            let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [] }

        var documents: [ConnectorDocument] = []
        walkSafariBookmarkNode(root, browser: browser, record: record, path: [], readingList: false, documents: &documents)
        return documents
    }

    private func walkSafariBookmarkNode(
        _ node: [String: Any],
        browser: BrowserKind,
        record: ConnectorRecord,
        path: [String],
        readingList: Bool,
        documents: inout [ConnectorDocument]
    ) {
        let title = node["Title"] as? String ?? ""
        let nextPath = title.isEmpty ? path : path + [title]
        let isReadingList = readingList || nextPath.joined(separator: "/").localizedCaseInsensitiveContains("reading")

        if let url = node["URLString"] as? String, !url.isEmpty {
            let dataType = isReadingList ? "readingList" : "bookmark"
            documents.append(document(
                record: record,
                browser: browser,
                dataType: dataType,
                externalID: "\(dataType):\(url)",
                title: title.isEmpty ? url : title,
                text: "URL: \(url)\nFolder: \(path.joined(separator: " / "))",
                url: url,
                timestamp: nil,
                extraMetadata: ["folder": path.joined(separator: " / ")]
            ))
        }

        for child in node["Children"] as? [[String: Any]] ?? [] {
            walkSafariBookmarkNode(child, browser: browser, record: record, path: nextPath, readingList: isReadingList, documents: &documents)
        }
    }

    private func historyDocuments(_ output: String, browser: BrowserKind, record: ConnectorRecord) -> [ConnectorDocument] {
        rows(output).compactMap { row in
            guard row.count >= 5 else { return nil }
            return document(
                record: record,
                browser: browser,
                dataType: "history",
                externalID: "history:\(row[0])",
                title: row[2].isEmpty ? row[1] : row[2],
                text: "URL: \(row[1])\nVisits: \(row[4])",
                url: row[1],
                timestamp: row[3],
                extraMetadata: ["visitCount": row[4]]
            )
        }
    }

    private func downloadDocuments(_ output: String, browser: BrowserKind, record: ConnectorRecord) -> [ConnectorDocument] {
        rows(output).compactMap { row in
            guard row.count >= 5 else { return nil }
            return document(
                record: record,
                browser: browser,
                dataType: "download",
                externalID: "download:\(row[0])",
                title: row[2].isEmpty ? row[1] : row[2],
                text: "URL: \(row[1])\nDownloaded file: \(row[2])\nBytes: \(row[4])",
                url: row[1],
                timestamp: row[3],
                extraMetadata: ["bytes": row[4]]
            )
        }
    }

    private func openTabDocuments(browser: BrowserKind, record: ConnectorRecord) async -> [ConnectorDocument] {
        guard browser != .genericChromium else { return [] }
        return await tabProvider.snapshots(for: browser).enumerated().map { offset, tab in
            document(
                record: record,
                browser: browser,
                dataType: "openTab",
                externalID: "openTab:\(offset):\(tab.url)",
                title: tab.title,
                text: "URL: \(tab.url)\nCurrent open tab",
                url: tab.url,
                timestamp: nil
            )
        }
    }

    private func document(
        record: ConnectorRecord,
        browser: BrowserKind,
        dataType: String,
        externalID: String,
        title: String,
        text: String,
        url: String,
        timestamp: String?,
        extraMetadata: [String: String] = [:]
    ) -> ConnectorDocument {
        var metadata = extraMetadata
        let browserDisplayName = record.configuration.browserDisplayName ?? browser.displayName
        metadata["browser"] = browserDisplayName
        metadata["profile"] = record.configuration.browserProfileName ?? record.displayName
        metadata["dataType"] = dataType
        metadata["url"] = url
        if let timestamp, !timestamp.isEmpty { metadata["timestamp"] = timestamp }
        return ConnectorDocument(
            connectorID: record.id,
            externalID: "\(browser.rawValue):\(externalID)",
            title: title,
            text: text,
            sourceLabel: "\(browserDisplayName) · \(dataType)",
            metadata: metadata
        )
    }

    private func rows(_ output: String) -> [[String]] {
        output.split(whereSeparator: \.isNewline).map {
            $0.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
        }
    }
}

private let chromiumHistoryQuery = """
SELECT id, url, COALESCE(title, ''), COALESCE(datetime(last_visit_time / 1000000 - 11644473600, 'unixepoch'), ''), COALESCE(visit_count, 0)
FROM urls
ORDER BY last_visit_time DESC
LIMIT 10000;
"""

private let chromiumDownloadsQuery = """
SELECT id, COALESCE(tab_url, ''), COALESCE(target_path, ''), COALESCE(datetime(start_time / 1000000 - 11644473600, 'unixepoch'), ''), COALESCE(total_bytes, 0)
FROM downloads
ORDER BY start_time DESC;
"""

private let firefoxBookmarksQuery = """
SELECT b.id, p.url, COALESCE(b.title, p.title, ''), COALESCE(parent.title, ''), COALESCE(datetime(b.dateAdded / 1000000, 'unixepoch'), '')
FROM moz_bookmarks b
JOIN moz_places p ON p.id = b.fk
LEFT JOIN moz_bookmarks parent ON parent.id = b.parent
WHERE b.type = 1
ORDER BY b.dateAdded DESC;
"""

private let firefoxHistoryQuery = """
SELECT id, url, COALESCE(title, ''), COALESCE(datetime(last_visit_date / 1000000, 'unixepoch'), ''), COALESCE(visit_count, 0)
FROM moz_places
WHERE last_visit_date IS NOT NULL
ORDER BY last_visit_date DESC
LIMIT 10000;
"""

private let firefoxDownloadsQuery = """
SELECT a.id, COALESCE(p.url, ''), REPLACE(COALESCE(a.content, ''), 'file://', ''), COALESCE(datetime(a.dateAdded / 1000000, 'unixepoch'), ''), COALESCE(p.visit_count, 0)
FROM moz_annos a
JOIN moz_anno_attributes attr ON attr.id = a.anno_attribute_id
LEFT JOIN moz_places p ON p.id = a.place_id
WHERE attr.name = 'downloads/destinationFileURI'
ORDER BY a.dateAdded DESC;
"""
