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
            memoryUsage: currentMemoryUsage()
        )
    }

    private func currentMemoryUsage() -> SystemMemoryUsage? {
        let host = mach_host_self()
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }

        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let multiplier = UInt64(pageSize)
        func bytes(_ count: natural_t) -> UInt64 { UInt64(count) * multiplier }
        return SystemMemoryUsage(
            pageSize: multiplier,
            freeBytes: bytes(statistics.free_count),
            activeBytes: bytes(statistics.active_count),
            inactiveBytes: bytes(statistics.inactive_count),
            wiredBytes: bytes(statistics.wire_count),
            compressedBytes: bytes(statistics.compressor_page_count),
            purgeableBytes: bytes(statistics.purgeable_count)
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
}
