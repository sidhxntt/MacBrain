import Foundation

struct ConnectorQueryResult: Equatable, Sendable {
    let operation: ConnectorQueryOperation
    let totalCount: Int?
    let documents: [ConnectorDocument]
    let capturedAt: Date
}

enum ConnectorQueryExecution: Equatable, Sendable {
    case result(ConnectorQueryResult, sourceKinds: Set<SourceConnectorKind>)
    case notConnected(requestedKinds: Set<SourceConnectorKind>)
    case permissionNeeded(sourceKinds: Set<SourceConnectorKind>)
    case indexUnavailable(sourceKinds: Set<SourceConnectorKind>)
    case failed(String)
}
