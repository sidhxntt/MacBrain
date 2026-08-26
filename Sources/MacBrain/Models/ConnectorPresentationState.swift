import Foundation

enum ConnectorPresentationState: Equatable, Sendable {
    case connecting
    case syncing(progress: String?)
    case refreshing(documentCount: Int, lastSuccessfulSync: Date?)
    case ready(documentCount: Int, lastSuccessfulSync: Date?)
    case empty(lastSuccessfulSync: Date?)
    case paused(documentCount: Int, hasSearchableIndex: Bool)
    case needsAuthorization(documentCount: Int, hasSearchableIndex: Bool)
    case failed(documentCount: Int, hasSearchableIndex: Bool)

    init(record: ConnectorRecord, health: ConnectorIndexHealth?) {
        let verifiedHealth = health.flatMap { candidate in
            candidate.sourceID == record.id && candidate.isSearchable ? candidate : nil
        }
        let verifiedDocumentCount = verifiedHealth?.documentCount ?? 0

        switch record.status {
        case .ready:
            guard let verifiedHealth else {
                self = .connecting
                return
            }
            if verifiedHealth.documentCount == 0 {
                self = .empty(lastSuccessfulSync: verifiedHealth.lastSuccessfulSync)
            } else {
                self = .ready(
                    documentCount: verifiedHealth.documentCount,
                    lastSuccessfulSync: verifiedHealth.lastSuccessfulSync
                )
            }
        case .syncing:
            if let verifiedHealth {
                self = .refreshing(
                    documentCount: verifiedHealth.documentCount,
                    lastSuccessfulSync: verifiedHealth.lastSuccessfulSync
                )
            } else if record.lastSuccessfulSync == nil, record.syncProgress == nil {
                self = .connecting
            } else {
                self = .syncing(progress: record.syncProgress)
            }
        case .paused:
            self = .paused(
                documentCount: verifiedDocumentCount,
                hasSearchableIndex: verifiedHealth != nil
            )
        case .needsAuthorization:
            self = .needsAuthorization(
                documentCount: verifiedDocumentCount,
                hasSearchableIndex: verifiedHealth != nil
            )
        case .failed:
            self = .failed(
                documentCount: verifiedDocumentCount,
                hasSearchableIndex: verifiedHealth != nil
            )
        }
    }
}
