import Foundation

struct CitationSourceLocation: Equatable, Sendable {
    let reference: String
    let url: URL?

    static func resolve(
        sourceType: String,
        externalID: String,
        metadata: [String: String]
    ) -> Self {
        let path = metadata["path"]?.trimmedNonEmpty
        let relativePath = metadata["relativePath"]?.trimmedNonEmpty
        let metadataURL = metadata["url"]?.trimmedNonEmpty
        let reference = path ?? relativePath ?? metadataURL ?? externalID

        if let metadataURL, let url = safeURL(from: metadataURL) {
            return Self(reference: reference, url: url)
        }

        let fileBackedTypes: Set<String> = [
            SourceConnectorKind.folder.rawValue,
            SourceConnectorKind.gitRepository.rawValue,
            SourceConnectorKind.books.rawValue,
        ]
        if fileBackedTypes.contains(sourceType),
           let filePath = path ?? (externalID.hasPrefix("/") ? externalID : nil),
           (filePath as NSString).isAbsolutePath {
            return Self(reference: reference, url: URL(fileURLWithPath: filePath))
        }

        return Self(reference: reference, url: nil)
    }

    private static func safeURL(from value: String) -> URL? {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return nil }
        if url.isFileURL {
            return (url.path as NSString).isAbsolutePath ? url : nil
        }
        return ["http", "https"].contains(scheme) && url.host != nil ? url : nil
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
