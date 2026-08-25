import Foundation

struct DeterministicGraphExtractor: Sendable {
    func extract(from chunks: [StoredChunk]) -> GraphMutation {
        var result = GraphMutation()
        var entities: [String: GraphEntity] = [:]
        func add(_ type: GraphEntityType, _ name: String, chunk: StoredChunk, range: NSRange, confidence: Double) {
            let key = "\(chunk.sourceID.uuidString)|\(type.rawValue)|\(name.lowercased())"
            let entity = entities[key] ?? GraphEntity(sourceID: chunk.sourceID, type: type, name: name, confidence: confidence)
            entities[key] = entity
            result.mentions.append(GraphMention(entityID: entity.id, provenanceChunkID: chunk.id, startOffset: range.location, endOffset: range.location + range.length, confidence: confidence))
        }
        for chunk in chunks {
            let text = chunk.text
            for match in matches("(?im)^#\\s*(?:project|decision|topic)\\s*:\\s*([^\\n#]+)", in: text) {
                let value = (text as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                let heading = (text as NSString).substring(with: match.range(at: 0)).lowercased()
                add(heading.contains("decision") ? .decision : heading.contains("topic") ? .topic : .project, value, chunk: chunk, range: match.range(at: 1), confidence: 0.98)
            }
            for match in matches("(?:https?://)?github\\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)", in: text) { add(.repository, (text as NSString).substring(with: match.range(at: 1)), chunk: chunk, range: match.range(at: 1), confidence: 0.98) }
            for match in matches("(?<!\\w)(?:[A-Za-z0-9_.-]+/)+[A-Za-z0-9_.-]+\\.[A-Za-z0-9]+", in: text) { add(.document, (text as NSString).substring(with: match.range), chunk: chunk, range: match.range, confidence: 0.94) }
            for match in matches("\\b\\d{4}-\\d{2}-\\d{2}\\b", in: text) { add(.date, (text as NSString).substring(with: match.range), chunk: chunk, range: match.range, confidence: 0.98) }
            var nameCounts: [String: [NSRange]] = [:]
            for match in matches("\\b([A-Z][a-z]+\\s+[A-Z][a-z]+)\\b", in: text) { let name = (text as NSString).substring(with: match.range(at: 1)); nameCounts[name, default: []].append(match.range(at: 1)) }
            for (name, ranges) in nameCounts where ranges.count > 1 { for range in ranges { add(.person, name, chunk: chunk, range: range, confidence: 0.82) } }
        }
        result.entities = Array(entities.values)
        for chunk in chunks {
            let local = result.mentions.filter { $0.provenanceChunkID == chunk.id }.compactMap { mention in result.entities.first { $0.id == mention.entityID } }
            for person in local.filter({ $0.type == .person }) { for project in local.filter({ $0.type == .project }) { if chunk.text.localizedCaseInsensitiveContains("works on") { result.relationships.append(GraphRelationship(fromEntityID: person.id, toEntityID: project.id, type: .worksOn, provenanceChunkID: chunk.id, confidence: 0.82)) } } }
        }
        return result
    }
    private func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] { (try? NSRegularExpression(pattern: pattern)).map { $0.matches(in: text, range: NSRange(text.startIndex..., in: text)) } ?? [] }
}
