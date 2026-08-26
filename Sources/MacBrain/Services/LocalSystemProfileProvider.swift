import Darwin
import Foundation

struct LocalSystemProfileProvider: SystemProfileProviding {
    func currentProfile() -> SystemProfile {
        let processInfo = ProcessInfo.processInfo
        let version = processInfo.operatingSystemVersion
        let fileSystem = (try? FileManager.default.attributesOfFileSystem(forPath: "/")) ?? [:]

        return SystemProfile(
            userDisplayName: NSFullUserName(),
            computerName: Host.current().localizedName ?? processInfo.hostName,
            hardwareModel: sysctlValue("hw.model") ?? "Unknown Mac",
            processor: sysctlValue("machdep.cpu.brand_string") ?? "Apple silicon",
            memoryBytes: processInfo.physicalMemory,
            operatingSystem: "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion) (\(processInfo.operatingSystemVersionString))",
            totalDiskBytes: (fileSystem[.systemSize] as? NSNumber)?.int64Value ?? 0,
            availableDiskBytes: (fileSystem[.systemFreeSize] as? NSNumber)?.int64Value ?? 0,
            localeIdentifier: Locale.current.identifier,
            timeZoneIdentifier: TimeZone.current.identifier,
            memoryUsage: LocalLiveMacContextProvider.currentMemoryUsage(),
            architecture: sysctlValue("hw.machine") ?? "Unknown",
            physicalCPUCount: sysctlInteger("hw.physicalcpu"),
            logicalCPUCount: sysctlInteger("hw.logicalcpu") ?? processInfo.processorCount,
            performanceCoreCount: sysctlInteger("hw.perflevel0.physicalcpu"),
            efficiencyCoreCount: sysctlInteger("hw.perflevel1.physicalcpu")
        )
    }

    private func sysctlValue(_ name: String) -> String? {
        var length = 0
        guard sysctlbyname(name, nil, &length, nil, 0) == 0, length > 0 else { return nil }

        var buffer = [CChar](repeating: 0, count: length)
        guard sysctlbyname(name, &buffer, &length, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func sysctlInteger(_ name: String) -> Int? {
        var value: Int32 = 0
        var length = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &length, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}
