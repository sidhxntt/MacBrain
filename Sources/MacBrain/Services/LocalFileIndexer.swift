import Foundation
import PDFKit

enum LocalFileIndexer {
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
        "node_modules", "build", ".build", "deriveddata", "dist", "vendor", "pods"
    ]
    private static let maximumFileSize = 10 * 1_024 * 1_024

    static func documents(
        rootURL: URL,
        connectorID: UUID,
        sourceLabel: String,
        allowedRelativePaths: Set<String>? = nil
    ) throws -> [ConnectorDocument] {
        let values = try rootURL.resourceValues(forKeys: [.isDirectoryKey])
        let fileURLs: [URL]
        if values.isDirectory == true {
            fileURLs = try recursiveFiles(in: rootURL)
        } else {
            fileURLs = [rootURL]
        }

        return fileURLs.compactMap { url in
            let relativePath = relativePath(for: url, rootURL: rootURL)
            guard allowedRelativePaths == nil || allowedRelativePaths?.contains(relativePath) == true else { return nil }
            return document(for: url, relativePath: relativePath, connectorID: connectorID, sourceLabel: sourceLabel)
        }
    }

    private static func recursiveFiles(in rootURL: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
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
            if shouldExclude(relativePath: relativePath) {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true,
                  (values.fileSize ?? 0) <= maximumFileSize,
                  isSupported(url) else { continue }
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func shouldExclude(relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/").map { $0.lowercased() }
        return components.contains(where: { excludedDirectoryNames.contains($0) })
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

    private static func document(
        for url: URL,
        relativePath: String,
        connectorID: UUID,
        sourceLabel: String
    ) -> ConnectorDocument? {
        let extensionName = url.pathExtension.lowercased()
        let text: String
        let metadata: [String: String]
        if extensionName == "pdf" {
            guard let document = PDFDocument(url: url) else { return nil }
            text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n\n")
            metadata = ["format": "pdf", "pageCount": String(document.pageCount)]
        } else {
            guard let rawText = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            text = extensionName == "srt" || extensionName == "vtt" ? cleanCaptions(rawText) : rawText
            metadata = ["format": extensionName]
        }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }
        let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        var completeMetadata = metadata
        completeMetadata["path"] = url.path
        completeMetadata["relativePath"] = relativePath
        return ConnectorDocument(
            connectorID: connectorID,
            externalID: url.standardizedFileURL.path,
            title: title(for: trimmedText, fallback: url.deletingPathExtension().lastPathComponent),
            text: trimmedText,
            sourceLabel: sourceLabel,
            createdAt: resourceValues?.creationDate,
            modifiedAt: resourceValues?.contentModificationDate,
            metadata: completeMetadata
        )
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
}
