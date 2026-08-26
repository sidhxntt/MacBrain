import Foundation
import PDFKit

enum LocalFileIndexer {
    struct ScanResult: Sendable {
        let changedDocuments: [ConnectorDocument]
        let presentExternalIDs: [String]
        let fingerprints: [String: FileFingerprint]
    }

    static let supportedExtensions: Set<String> = [
        "txt", "md", "markdown", "pdf", "srt", "vtt",
        "swift", "m", "mm", "c", "h", "cpp", "hpp", "cc",
        "js", "jsx", "ts", "tsx", "json", "yaml", "yml", "toml", "xml",
        "py", "rb", "go", "rs", "java", "kt", "kts", "cs", "php",
        "html", "css", "scss", "sql", "sh", "zsh", "fish", "makefile"
    ]
    private static let supportedSecretExtensions: Set<String> = [
        "pem", "key", "crt", "cer", "p12", "pfx"
    ]
    private static let excludedDirectoryNames: Set<String> = [
        ".git", "node_modules", "build", ".build", "deriveddata", "dist", "vendor", "pods"
    ]
    private static let maximumFileSize = 10 * 1_024 * 1_024

    static func documents(
        rootURL: URL,
        connectorID: UUID,
        sourceLabel: String,
        allowedRelativePaths: Set<String>? = nil,
        excludedRelativePaths: [String] = []
    ) throws -> [ConnectorDocument] {
        try scan(
            rootURL: rootURL,
            connectorID: connectorID,
            sourceLabel: sourceLabel,
            allowedRelativePaths: allowedRelativePaths,
            excludedRelativePaths: excludedRelativePaths
        ).changedDocuments
    }

    static func scan(
        rootURL: URL,
        connectorID: UUID,
        sourceLabel: String,
        knownFingerprints: [String: FileFingerprint] = [:],
        allowedRelativePaths: Set<String>? = nil,
        excludedRelativePaths: [String] = []
    ) throws -> ScanResult {
        let values = try rootURL.resourceValues(forKeys: [.isDirectoryKey])
        let fileURLs: [URL]
        if values.isDirectory == true {
            fileURLs = try recursiveFiles(
                in: rootURL,
                allowedRelativePaths: allowedRelativePaths,
                excludedRelativePaths: excludedRelativePaths
            )
        } else {
            fileURLs = [rootURL]
        }

        var changedDocuments: [ConnectorDocument] = []
        var presentExternalIDs: [String] = []
        var fingerprints: [String: FileFingerprint] = [:]
        for url in fileURLs {
            let relativePath = relativePath(for: url, rootURL: rootURL)
            guard allowedRelativePaths == nil || allowedRelativePaths?.contains(relativePath) == true else { continue }
            let key = url.standardizedFileURL.path
            let currentFingerprint = fingerprint(for: url, documentExternalIDs: knownFingerprints[key]?.documentExternalIDs ?? [])
            if let existing = knownFingerprints[key], existing.byteCount == currentFingerprint.byteCount, existing.modifiedAt == currentFingerprint.modifiedAt {
                fingerprints[key] = existing
                presentExternalIDs.append(contentsOf: existing.documentExternalIDs)
                continue
            }
            let documents = documents(for: url, relativePath: relativePath, connectorID: connectorID, sourceLabel: sourceLabel)
            guard !documents.isEmpty else { continue }
            let updatedFingerprint = fingerprint(for: url, documentExternalIDs: documents.map(\.externalID))
            fingerprints[key] = updatedFingerprint
            presentExternalIDs.append(contentsOf: updatedFingerprint.documentExternalIDs)
            changedDocuments.append(contentsOf: documents)
        }
        return ScanResult(
            changedDocuments: changedDocuments.sorted { $0.externalID < $1.externalID },
            presentExternalIDs: presentExternalIDs.sorted(),
            fingerprints: fingerprints
        )
    }

    private static func recursiveFiles(
        in rootURL: URL,
        allowedRelativePaths: Set<String>?,
        excludedRelativePaths: [String]
    ) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else {
            throw ConnectorError.sourceUnavailable("The selected folder could not be read.")
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let relativePath = relativePath(for: url, rootURL: rootURL)
            let values = try? url.resourceValues(forKeys: keys)
            if shouldExclude(relativePath: relativePath, excludedRelativePaths: excludedRelativePaths) {
                if values?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            if let allowedRelativePaths, values?.isDirectory == true,
               !allowedRelativePaths.contains(where: { $0.hasPrefix(relativePath + "/") }) {
                enumerator.skipDescendants()
                continue
            }
            guard allowedRelativePaths == nil || allowedRelativePaths?.contains(relativePath) == true,
                  let values, values.isRegularFile == true,
                  (values.fileSize ?? 0) <= maximumFileSize,
                  isSupported(url) else { continue }
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func shouldExclude(relativePath: String, excludedRelativePaths: [String]) -> Bool {
        let components = relativePath.split(separator: "/").map { $0.lowercased() }
        if components.contains(where: { excludedDirectoryNames.contains($0) }) { return true }
        let normalizedPath = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return excludedRelativePaths.contains { exclusion in
            let normalizedExclusion = exclusion.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return normalizedPath == normalizedExclusion || normalizedPath.hasPrefix(normalizedExclusion + "/")
        }
    }

    private static func isSupported(_ url: URL) -> Bool {
        let fileName = url.lastPathComponent.lowercased()
        let extensionName = url.pathExtension.lowercased()
        return fileName == ".env"
            || fileName.hasPrefix(".env.")
            || extensionName.isEmpty
            || supportedExtensions.contains(extensionName)
            || supportedSecretExtensions.contains(extensionName)
    }

    private static func documents(
        for url: URL,
        relativePath: String,
        connectorID: UUID,
        sourceLabel: String
    ) -> [ConnectorDocument] {
        let extensionName = url.pathExtension.lowercased()
        let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        if extensionName == "pdf" {
            guard let document = PDFDocument(url: url) else { return [] }
            return pdfDocuments(
                pageTexts: (0..<document.pageCount).compactMap { document.page(at: $0)?.string },
                url: url,
                relativePath: relativePath,
                connectorID: connectorID,
                sourceLabel: sourceLabel,
                createdAt: resourceValues?.creationDate,
                modifiedAt: resourceValues?.contentModificationDate
            )
        }
        guard let rawText = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let text = extensionName == "srt" || extensionName == "vtt" ? cleanCaptions(rawText) : rawText
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return [] }
        var completeMetadata = ["format": extensionName]
        completeMetadata["path"] = url.path
        completeMetadata["relativePath"] = relativePath
        return [ConnectorDocument(
            connectorID: connectorID,
            externalID: url.standardizedFileURL.path,
            title: title(for: trimmedText, fallback: url.deletingPathExtension().lastPathComponent),
            text: trimmedText,
            sourceLabel: sourceLabel,
            createdAt: resourceValues?.creationDate,
            modifiedAt: resourceValues?.contentModificationDate,
            metadata: completeMetadata
        )]
    }

    static func pdfDocuments(
        pageTexts: [String],
        url: URL,
        relativePath: String,
        connectorID: UUID,
        sourceLabel: String,
        createdAt: Date?,
        modifiedAt: Date?
    ) -> [ConnectorDocument] {
        pageTexts.enumerated().compactMap { index, rawText in
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let pageNumber = index + 1
            return ConnectorDocument(
                connectorID: connectorID,
                externalID: "\(url.standardizedFileURL.path)#page-\(pageNumber)",
                title: "\(url.deletingPathExtension().lastPathComponent) · page \(pageNumber)",
                text: text,
                sourceLabel: sourceLabel,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                metadata: [
                    "format": "pdf",
                    "path": url.path,
                    "relativePath": relativePath,
                    "pageNumber": String(pageNumber)
                ]
            )
        }
    }

    private static func relativePath(for url: URL, rootURL: URL) -> String {
        guard (try? rootURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            return rootURL.lastPathComponent
        }
        let prefix = rootURL.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.replacingOccurrences(of: prefix, with: "")
    }

    private static func title(for text: String, fallback: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
            .flatMap { $0.isEmpty ? nil : $0 } ?? fallback
    }

    private static func cleanCaptions(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && !trimmed.contains("-->") && Int(trimmed) == nil && trimmed != "WEBVTT"
            }
            .joined(separator: "\n")
    }

    private static func fingerprint(for url: URL, documentExternalIDs: [String]) -> FileFingerprint {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return FileFingerprint(
            byteCount: Int64(values?.fileSize ?? 0),
            modifiedAt: values?.contentModificationDate,
            documentExternalIDs: documentExternalIDs.sorted()
        )
    }
}
