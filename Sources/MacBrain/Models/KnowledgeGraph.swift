import Foundation

enum GraphEntityType: String, Codable, CaseIterable, Sendable { case person, project, repository, document, decision, organization, topic, date }
enum GraphRelationshipType: String, Codable, CaseIterable, Sendable { case mentions, belongsToProject = "belongs_to_project", worksOn = "works_on", madeDecision = "made_decision", supportedBy = "supported_by", relatedTo = "related_to", supersedes }

struct GraphEntity: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceID: UUID
    var type: GraphEntityType
    var name: String
    var confidence: Double
    init(id: UUID = UUID(), sourceID: UUID, type: GraphEntityType, name: String, confidence: Double) { self.id = id; self.sourceID = sourceID; self.type = type; self.name = name; self.confidence = confidence }
}

struct GraphAlias: Equatable, Sendable { let entityID: UUID; let value: String; let confidence: Double }
struct GraphMention: Identifiable, Equatable, Sendable { let id: UUID; let entityID: UUID; let provenanceChunkID: UUID; let startOffset: Int; let endOffset: Int; let confidence: Double; init(id: UUID = UUID(), entityID: UUID, provenanceChunkID: UUID, startOffset: Int, endOffset: Int, confidence: Double) { self.id = id; self.entityID = entityID; self.provenanceChunkID = provenanceChunkID; self.startOffset = startOffset; self.endOffset = endOffset; self.confidence = confidence } }
struct GraphRelationship: Identifiable, Equatable, Sendable { let id: UUID; let fromEntityID: UUID; let toEntityID: UUID; let type: GraphRelationshipType; let provenanceChunkID: UUID; let confidence: Double; init(id: UUID = UUID(), fromEntityID: UUID, toEntityID: UUID, type: GraphRelationshipType, provenanceChunkID: UUID, confidence: Double) { self.id = id; self.fromEntityID = fromEntityID; self.toEntityID = toEntityID; self.type = type; self.provenanceChunkID = provenanceChunkID; self.confidence = confidence } }
struct GraphMutation: Sendable { var entities: [GraphEntity] = []; var aliases: [GraphAlias] = []; var mentions: [GraphMention] = []; var relationships: [GraphRelationship] = [] }
struct GraphEvidence: Identifiable, Equatable, Sendable { let relationship: GraphRelationship; let from: GraphEntity; let to: GraphEntity; var id: UUID { relationship.id } }
