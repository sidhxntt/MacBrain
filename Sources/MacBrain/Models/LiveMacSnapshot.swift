import Foundation

enum LiveMacCapability: String, CaseIterable, Sendable, Hashable {
    case memory
    case processor
    case storage
    case power
    case network
    case applications
    case uptime
}

struct LiveMacSnapshot: Sendable, Equatable {
    let capturedAt: Date
    let memory: SystemMemoryUsage
    let storage: Storage
    let uptimeSeconds: TimeInterval
    let cpuLoadAverages: [Double]
    let power: Power?
    let activeApplicationName: String?
    let runningApplicationNames: [String]
    let networkInterfaces: [String]

    struct Storage: Sendable, Equatable {
        let totalBytes: Int64
        let availableBytes: Int64
    }

    struct Power: Sendable, Equatable {
        let percentage: Int?
        let isCharging: Bool?
        let source: String?
    }
}

protocol LiveMacContextProviding: Sendable {
    func snapshot(for capabilities: Set<LiveMacCapability>) async -> LiveMacSnapshot
}

extension LiveMacContextProviding {
    func snapshot() async -> LiveMacSnapshot {
        await snapshot(for: Set(LiveMacCapability.allCases))
    }
}
