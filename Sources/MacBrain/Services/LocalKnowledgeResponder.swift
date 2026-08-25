import Foundation

struct LocalKnowledgeResponder: ChatResponder {
    let repository: LocalSourceRepository

    func respond(to prompt: String) async throws -> String {
        let matches = await repository.search(prompt)
        guard !matches.isEmpty else {
            return "I don't have matching local source material yet. Add a selected Note folder, Mail mailbox, local folder, or Git repository with the + button."
        }

        let evidence = matches.prefix(3).map { document in
            let excerpt = document.text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "• \(document.title) — \(String(excerpt.prefix(280)))\n  Source: \(document.sourceLabel)"
        }.joined(separator: "\n\n")

        let graphEvidence = await repository.graphEvidence(for: prompt)
        let graphSection = graphEvidence.isEmpty ? "" : "\n\nGraph-derived relationships (not direct excerpts):\n" + graphEvidence.map {
            "• \($0.from.name) — \($0.relationship.type.rawValue.replacingOccurrences(of: "_", with: " ")) → \($0.to.name)"
        }.joined(separator: "\n")

        return "I found local evidence related to \"\(prompt)\":\n\n\(evidence)\(graphSection)\n\nThese results stay on your Mac."
    }
}
