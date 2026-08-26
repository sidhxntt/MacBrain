import CryptoKit
import Foundation

struct ConnectorIndexHealth: Codable, Equatable, Sendable {
    let sourceID: UUID
    var documentCount: Int
    var chunkCount: Int
    var contentRevision: String
    var initialSyncCompleted: Bool
    var lastSuccessfulSync: Date?
    var lastVerifiedAt: Date?
    var lastError: String?

    init(
        sourceID: UUID,
        documentCount: Int = 0,
        chunkCount: Int = 0,
        contentRevision: String = "",
        initialSyncCompleted: Bool = false,
        lastSuccessfulSync: Date? = nil,
        lastVerifiedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.sourceID = sourceID
        self.documentCount = documentCount
        self.chunkCount = chunkCount
        self.contentRevision = contentRevision
        self.initialSyncCompleted = initialSyncCompleted
        self.lastSuccessfulSync = lastSuccessfulSync
        self.lastVerifiedAt = lastVerifiedAt
        self.lastError = lastError
    }

    var isSearchable: Bool {
        initialSyncCompleted && lastVerifiedAt != nil
    }

    var isEmpty: Bool {
        isSearchable && documentCount == 0
    }
}

struct SourceContentRevisionEntry: Sendable {
    let externalID: String
    let contentHash: String
    let createdAt: Date?
    let modifiedAt: Date?
    let metadata: [String: String]
}

enum SourceContentRevision {
    static func digest(_ entries: [SourceContentRevisionEntry]) -> String {
        let material = entries
            .sorted { $0.externalID < $1.externalID }
            .map { entry in
                let createdAt = entry.createdAt?.timeIntervalSince1970.description ?? ""
                let modifiedAt = entry.modifiedAt?.timeIntervalSince1970.description ?? ""
                let metadata = entry.metadata
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: "&")
                return "\(entry.externalID)|\(entry.contentHash)|\(createdAt)|\(modifiedAt)|\(metadata)"
            }
            .joined(separator: "\n")
        return SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
