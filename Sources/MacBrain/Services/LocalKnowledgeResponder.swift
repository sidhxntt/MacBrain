import Foundation

struct LocalKnowledgeResponder: ChatResponder {
    let repository: LocalSourceRepository

    func respond(to prompt: String) async throws -> String {
        let result = await repository.searchLexicalEvidence(prompt, limit: 3)
        guard !result.evidence.isEmpty else {
            return "I don't have matching local source material yet. Add a selected Note folder, Mail mailbox, local folder, or Git repository with the + button."
        }

        let evidence = result.evidence.map { source in
            let excerpt = source.excerpt
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "• [\(source.citationID)] \(source.sourceTitle) — \(String(excerpt.prefix(280)))\n  Source type: \(source.sourceType)"
        }.joined(separator: "\n\n")
        let sources = CitationValidator.renderedSources(for: result.evidence)
        return "I found matching local evidence:\n\n\(evidence)\n\n\(sources)\n\nThese results stay on your Mac."
    }
}
