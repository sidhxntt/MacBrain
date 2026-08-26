import Foundation

enum ConnectorQueryOperation: Equatable, Sendable {
    case count
    case newest(limit: Int)
    case oldest(limit: Int)
    case nextEvent
    case firstDueReminder
}

enum SystemQueryDomain: String, CaseIterable, Hashable, Sendable {
    case identity
    case specifications
    case memory
    case processor
    case storage
    case operatingSystem
    case power
    case applications
    case network
    case uptime
    case displays
}

struct SystemQueryPlan: Equatable, Sendable {
    enum ResponseStyle: Equatable, Sendable {
        case direct
        case synthesizedOverview
    }

    let domains: Set<SystemQueryDomain>
    let responseStyle: ResponseStyle
}

enum LocalQueryPlan: Equatable, Sendable {
    case restricted(response: String)
    case system(SystemQueryPlan)
    case connectorCapability(scope: Set<SourceConnectorKind>)
    case connector(ConnectorQueryOperation, scope: Set<SourceConnectorKind>?)
    case evidenceSearch(scope: Set<SourceConnectorKind>?)
    case casual
}
