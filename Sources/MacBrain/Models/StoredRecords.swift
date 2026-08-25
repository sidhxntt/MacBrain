import CryptoKit
import Foundation

struct StoredSource: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var kind: String
    var displayName: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), kind: String, displayName: String, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct StoredDocument: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let sourceID: UUID
    let externalID: String
    var title: String
    var text: String
    var sourceLabel: String
    var contentHash: String
    var createdAt: Date?
    var modifiedAt: Date?
    var isDeleted: Bool
    var metadata: [String: String]

    init(
        id: UUID = UUID(),
        sourceID: UUID,
        externalID: String,
        title: String,
        text: String,
        sourceLabel: String,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        isDeleted: Bool = false,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.sourceID = sourceID
        self.externalID = externalID
        self.title = title
        self.text = text
        self.sourceLabel = sourceLabel
        self.contentHash = Self.hash(title + "\n" + text + "\n" + sourceLabel)
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isDeleted = isDeleted
        self.metadata = metadata
    }

    private static func hash(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct StoredChunk: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let documentID: UUID
    let sourceID: UUID
    var text: String
    var startOffset: Int
    var endOffset: Int
    var pageNumber: Int?
    var lineStart: Int?
    var lineEnd: Int?

    init(
        id: UUID = UUID(),
        documentID: UUID,
        sourceID: UUID,
        text: String,
        startOffset: Int,
        endOffset: Int,
        pageNumber: Int? = nil,
        lineStart: Int? = nil,
        lineEnd: Int? = nil
    ) {
        self.id = id
        self.documentID = documentID
        self.sourceID = sourceID
        self.text = text
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.pageNumber = pageNumber
        self.lineStart = lineStart
        self.lineEnd = lineEnd
    }
}

struct StoredEmbedding: Codable, Equatable, Sendable {
    let chunkID: UUID
    var vector: [Float]
    var indexIdentifier: String
    var updatedAt: Date

    init(chunkID: UUID, vector: [Float], indexIdentifier: String, updatedAt: Date = .now) {
        self.chunkID = chunkID
        self.vector = vector
        self.indexIdentifier = indexIdentifier
        self.updatedAt = updatedAt
    }
}

enum StoredMessageRole: String, Codable, Equatable, Sendable { case user, assistant, system }

struct StoredConversation: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var greeting: String
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    var isPinned: Bool

    init(id: UUID = UUID(), title: String, greeting: String, createdAt: Date = .now, updatedAt: Date = .now, isArchived: Bool = false, isPinned: Bool = false) {
        self.id = id
        self.title = title
        self.greeting = greeting
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.isPinned = isPinned
    }
}

struct StoredMessage: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let conversationID: UUID
    var role: StoredMessageRole
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), conversationID: UUID, role: StoredMessageRole, text: String, createdAt: Date = .now) {
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

struct StoredMemory: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var ownerID: String
    var text: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), ownerID: String, text: String, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.ownerID = ownerID
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct StoredEntity: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var type: String
    var name: String
    var createdAt: Date

    init(id: UUID = UUID(), type: String, name: String, createdAt: Date = .now) {
        self.id = id
        self.type = type
        self.name = name
        self.createdAt = createdAt
    }
}

struct StoredMention: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let entityID: UUID
    let chunkID: UUID
    var startOffset: Int
    var endOffset: Int
    var confidence: Double

    init(id: UUID = UUID(), entityID: UUID, chunkID: UUID, startOffset: Int, endOffset: Int, confidence: Double) {
        self.id = id
        self.entityID = entityID
        self.chunkID = chunkID
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.confidence = confidence
    }
}

struct StoredRelationship: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let fromEntityID: UUID
    let toEntityID: UUID
    var type: String
    var provenanceChunkID: UUID?
    var confidence: Double

    init(id: UUID = UUID(), fromEntityID: UUID, toEntityID: UUID, type: String, provenanceChunkID: UUID? = nil, confidence: Double) {
        self.id = id
        self.fromEntityID = fromEntityID
        self.toEntityID = toEntityID
        self.type = type
        self.provenanceChunkID = provenanceChunkID
        self.confidence = confidence
    }
}

enum IndexingJobKind: String, Codable, CaseIterable, Hashable, Sendable {
    case embedding
    case graphExtraction
}

enum IndexingJobState: String, Codable, Equatable, Sendable {
    case pending
    case processing
    case completed
    case failed
    case cancelled
}

struct IndexingJob: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let sourceID: UUID
    var kind: IndexingJobKind
    var state: IndexingJobState
    var chunkIDs: [UUID]
    var attempts: Int
    var detail: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        sourceID: UUID,
        kind: IndexingJobKind,
        state: IndexingJobState = .pending,
        chunkIDs: [UUID] = [],
        attempts: Int = 0,
        detail: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.sourceID = sourceID
        self.kind = kind
        self.state = state
        self.chunkIDs = chunkIDs
        self.attempts = attempts
        self.detail = detail
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

protocol VectorStore: Sendable {
    func upsert(_ embedding: StoredEmbedding) async throws
    func nearest(to vector: [Float], limit: Int) async throws -> [UUID]
    func remove(chunkID: UUID) async throws
}
