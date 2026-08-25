import Foundation

struct SystemProfile: Sendable, Equatable {
    let userDisplayName: String
    let computerName: String
    let hardwareModel: String
    let processor: String
    let memoryBytes: UInt64
    let operatingSystem: String
    let totalDiskBytes: Int64
    let availableDiskBytes: Int64
    let localeIdentifier: String
    let timeZoneIdentifier: String
    let memoryUsage: SystemMemoryUsage?

    init(
        userDisplayName: String,
        computerName: String,
        hardwareModel: String,
        processor: String,
        memoryBytes: UInt64,
        operatingSystem: String,
        totalDiskBytes: Int64,
        availableDiskBytes: Int64,
        localeIdentifier: String,
        timeZoneIdentifier: String,
        memoryUsage: SystemMemoryUsage? = nil
    ) {
        self.userDisplayName = userDisplayName
        self.computerName = computerName
        self.hardwareModel = hardwareModel
        self.processor = processor
        self.memoryBytes = memoryBytes
        self.operatingSystem = operatingSystem
        self.totalDiskBytes = totalDiskBytes
        self.availableDiskBytes = availableDiskBytes
        self.localeIdentifier = localeIdentifier
        self.timeZoneIdentifier = timeZoneIdentifier
        self.memoryUsage = memoryUsage
    }

    var promptContext: String {
        """
        Local Mac context, supplied by the user’s device: user display name: \(userDisplayName); computer: \(computerName) (\(hardwareModel)); processor: \(processor); memory: \(byteCount(memoryBytes)); operating system: \(operatingSystem); storage: \(byteCount(totalDiskBytes)) total, \(byteCount(availableDiskBytes)) available; locale: \(localeIdentifier); time zone: \(timeZoneIdentifier).
        \(memoryUsage?.promptContext ?? "")
        """
    }

    var liveMemoryResponse: String? {
        memoryUsage.map { $0.markdownBreakdown(totalMemoryBytes: memoryBytes) }
    }

    var markdownSummary: String {
        """
        ## Your Mac

        - **User:** \(userDisplayName)
        - **Computer:** \(computerName)
        - **Model:** \(hardwareModel)
        - **Processor:** \(processor)
        - **Memory:** \(byteCount(memoryBytes))
        - **macOS:** \(operatingSystem)
        - **Storage:** \(byteCount(totalDiskBytes)) total · \(byteCount(availableDiskBytes)) available
        - **Region:** \(localeIdentifier) · \(timeZoneIdentifier)
        """
    }

    private func byteCount(_ value: some BinaryInteger) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .decimal)
    }
}

struct SystemMemoryUsage: Sendable, Equatable {
    let pageSize: UInt64
    let freeBytes: UInt64
    let activeBytes: UInt64
    let inactiveBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let purgeableBytes: UInt64

    var reclaimableBytes: UInt64 { inactiveBytes }

    func markdownBreakdown(totalMemoryBytes: UInt64) -> String {
        let usedEstimate = totalMemoryBytes > freeBytes + reclaimableBytes
            ? totalMemoryBytes - freeBytes - reclaimableBytes
            : 0
        return """
        ## Memory now

        - Installed: \(byteCount(totalMemoryBytes))
        - In use estimate: \(byteCount(usedEstimate))
        - Free now: \(byteCount(freeBytes))
        - Reclaimable estimate: \(byteCount(reclaimableBytes))

        ### Breakdown

        - Active: \(byteCount(activeBytes))
        - Wired: \(byteCount(wiredBytes))
        - Compressed: \(byteCount(compressedBytes))
        - Inactive: \(byteCount(inactiveBytes))
        - Purgeable: \(byteCount(purgeableBytes))

        Values are sampled live from macOS virtual-memory counters. “Free now” is immediately unused memory; macOS can also reclaim inactive memory when apps need it.
        """
    }

    var promptContext: String {
        "Live memory snapshot: free now: \(byteCount(freeBytes)); reclaimable estimate: \(byteCount(reclaimableBytes)); active: \(byteCount(activeBytes)); wired: \(byteCount(wiredBytes)); compressed: \(byteCount(compressedBytes))."
    }

    private func byteCount(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .decimal)
    }
}

protocol SystemProfileProviding: Sendable {
    func currentProfile() -> SystemProfile
}
