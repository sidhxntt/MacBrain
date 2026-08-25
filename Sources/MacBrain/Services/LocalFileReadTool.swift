import Foundation

/// Reads current text from a file already indexed under a user-approved local source.
/// It deliberately cannot discover arbitrary paths or modify files.
struct LocalFileReadTool: Sendable {
    private static let maximumResponseCharacters = 12_000

    let repository: LocalSourceRepository

    func response(for prompt: String) async -> String? {
        guard Self.isFileContentRequest(prompt), let requestedPath = Self.requestedPath(in: prompt) else {
            return nil
        }

        let matches = await repository.search(requestedPath)
        guard let document = matches.first(where: { Self.matches($0, requestedPath: requestedPath) }),
              let record = await repository.record(id: document.connectorID),
              record.kind == .folder || record.kind == .gitRepository,
              let content = try? readCurrentContent(of: document, in: record)
        else {
            return nil
        }

        let displayPath = document.metadata["relativePath"] ?? URL(fileURLWithPath: document.externalID).lastPathComponent
        let visibleContent = String(content.prefix(Self.maximumResponseCharacters))
        let truncationNotice = content.count > visibleContent.count
            ? "\n\n_Only the first \(Self.maximumResponseCharacters.formatted()) characters are shown._"
            : ""
        return "## \(displayPath)\n\n\(visibleContent)\(truncationNotice)"
    }

    private func readCurrentContent(of document: ConnectorDocument, in record: ConnectorRecord) throws -> String {
        let access = try SecurityScopedLocalAccess(configuration: record.configuration)
        defer { access.stop() }

        let candidatePath = document.metadata["path"] ?? document.externalID
        let candidate = URL(fileURLWithPath: candidatePath).resolvingSymlinksInPath().standardizedFileURL
        let root = access.url.resolvingSymlinksInPath().standardizedFileURL
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
            throw ConnectorError.permissionDenied("That file is outside the selected source.")
        }
        guard candidate.pathExtension.lowercased() != "pdf" else {
            throw ConnectorError.sourceUnavailable("Read PDF content from its indexed pages instead.")
        }
        return try String(contentsOf: candidate, encoding: .utf8)
    }

    private static func matches(_ document: ConnectorDocument, requestedPath: String) -> Bool {
        let candidates = [
            document.metadata["relativePath"],
            document.metadata["path"],
            document.externalID,
            URL(fileURLWithPath: document.externalID).lastPathComponent
        ].compactMap { $0?.lowercased() }
        let requested = requestedPath.lowercased()
        return candidates.contains { candidate in
            candidate == requested || candidate.hasSuffix("/" + requested)
        }
    }

    static func isFileContentRequest(_ prompt: String) -> Bool {
        let normalized = prompt.lowercased()
        let asksForContent = normalized.contains("what's there")
            || normalized.contains("what is there")
            || normalized.contains("what is in")
            || normalized.contains("contents of")
            || normalized.contains("content of")
            || normalized.contains("read ")
            || normalized.contains("show ")
        return asksForContent && requestedPath(in: prompt) != nil
    }

    private static func requestedPath(in prompt: String) -> String? {
        let punctuation = CharacterSet(charactersIn: ".,?!:;\\\"'`()[]{}")
        return prompt
            .split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: punctuation) }
            .last { token in
                token.contains(".") && !token.lowercased().hasPrefix("http")
            }
    }
}
