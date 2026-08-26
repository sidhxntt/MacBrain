import Foundation

enum LiveMacCapability: String, CaseIterable, Sendable, Hashable {
    case identity
    case specifications
    case memory
    case swap
    case processor
    case storage
    case volumes
    case operatingSystem
    case power
    case network
    case applications
    case uptime
    case displays
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
    let swap: Swap?
    let bootTime: Date?
    let displays: [Display]

    init(
        capturedAt: Date,
        memory: SystemMemoryUsage,
        storage: Storage,
        uptimeSeconds: TimeInterval,
        cpuLoadAverages: [Double],
        power: Power?,
        activeApplicationName: String?,
        runningApplicationNames: [String],
        networkInterfaces: [String],
        swap: Swap? = nil,
        bootTime: Date? = nil,
        displays: [Display] = []
    ) {
        self.capturedAt = capturedAt
        self.memory = memory
        self.storage = storage
        self.uptimeSeconds = uptimeSeconds
        self.cpuLoadAverages = cpuLoadAverages
        self.power = power
        self.activeApplicationName = activeApplicationName
        self.runningApplicationNames = runningApplicationNames
        self.networkInterfaces = networkInterfaces
        self.swap = swap
        self.bootTime = bootTime
        self.displays = displays
    }

    struct Storage: Sendable, Equatable {
        let totalBytes: Int64
        let availableBytes: Int64
        let volumes: [Volume]

        init(
            totalBytes: Int64,
            availableBytes: Int64,
            volumes: [Volume] = []
        ) {
            self.totalBytes = totalBytes
            self.availableBytes = availableBytes
            self.volumes = volumes
        }

        struct Volume: Sendable, Equatable {
            let name: String
            let totalBytes: Int64
            let availableBytes: Int64
        }
    }

    struct Power: Sendable, Equatable {
        let percentage: Int?
        let isCharging: Bool?
        let source: String?
        let cycleCount: Int?
        let condition: String?

        init(
            percentage: Int?,
            isCharging: Bool?,
            source: String?,
            cycleCount: Int? = nil,
            condition: String? = nil
        ) {
            self.percentage = percentage
            self.isCharging = isCharging
            self.source = source
            self.cycleCount = cycleCount
            self.condition = condition
        }
    }

    struct Swap: Sendable, Equatable {
        let totalBytes: UInt64
        let usedBytes: UInt64
    }

    struct Display: Sendable, Equatable {
        let name: String
        let pixelWidth: Int
        let pixelHeight: Int
        let scaleFactor: Double
        let isMain: Bool
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
