import AppKit
import Darwin
import Foundation
import IOKit.ps

struct LocalLiveMacContextProvider: LiveMacContextProviding {
    func snapshot(for capabilities: Set<LiveMacCapability>) async -> LiveMacSnapshot {
        let fileSystem = (try? FileManager.default.attributesOfFileSystem(forPath: "/")) ?? [:]
        let appState: (active: String?, running: [String]) = capabilities.contains(.applications)
            ? await MainActor.run { Self.applicationState() }
            : (nil, [])

        return LiveMacSnapshot(
            capturedAt: .now,
            memory: Self.currentMemoryUsage() ?? .empty,
            storage: .init(
                totalBytes: (fileSystem[.systemSize] as? NSNumber)?.int64Value ?? 0,
                availableBytes: (fileSystem[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            ),
            uptimeSeconds: Self.currentUptime(),
            cpuLoadAverages: Self.currentCPULoadAverages(),
            power: capabilities.contains(.power) ? Self.currentPower() : nil,
            activeApplicationName: appState.active,
            runningApplicationNames: appState.running,
            networkInterfaces: capabilities.contains(.network) ? Self.activeNetworkInterfaces() : []
        )
    }

    static func currentMemoryUsage() -> SystemMemoryUsage? {
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

    private static func currentUptime() -> TimeInterval {
        var bootTime = timeval()
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var size = MemoryLayout<timeval>.size
        guard sysctl(&mib, u_int(mib.count), &bootTime, &size, nil, 0) == 0 else { return 0 }
        return max(0, Date().timeIntervalSince1970 - TimeInterval(bootTime.tv_sec))
    }

    private static func currentCPULoadAverages() -> [Double] {
        var values = [Double](repeating: 0, count: 3)
        guard getloadavg(&values, Int32(values.count)) == values.count else { return [] }
        return values
    }

    private static func currentPower() -> LiveMacSnapshot.Power? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        else { return nil }

        let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int
        let maxCapacity = description[kIOPSMaxCapacityKey] as? Int
        let percentage: Int? = switch (currentCapacity, maxCapacity) {
        case let (current?, max?) where max > 0: Int((Double(current) / Double(max) * 100).rounded())
        default: nil
        }
        return .init(
            percentage: percentage,
            isCharging: description[kIOPSIsChargingKey] as? Bool,
            source: description[kIOPSPowerSourceStateKey] as? String
        )
    }

    @MainActor
    private static func applicationState() -> (active: String?, running: [String]) {
        let workspace = NSWorkspace.shared
        let running = workspace.runningApplications
            .compactMap(\.localizedName)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return (workspace.frontmostApplication?.localizedName, running)
    }

    private static func activeNetworkInterfaces() -> [String] {
        var firstInterface: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstInterface) == 0, let firstInterface else { return [] }
        defer { freeifaddrs(firstInterface) }

        var names = Set<String>()
        var current: UnsafeMutablePointer<ifaddrs>? = firstInterface
        while let interface = current {
            let flags = Int32(interface.pointee.ifa_flags)
            let isUp = flags & IFF_UP != 0
            let isRunning = flags & IFF_RUNNING != 0
            if isUp, isRunning, let name = interface.pointee.ifa_name.map({ String(cString: $0) }), name != "lo0" {
                names.insert(name)
            }
            current = interface.pointee.ifa_next
        }
        return names.sorted()
    }
}

private extension SystemMemoryUsage {
    static let empty = SystemMemoryUsage(
        pageSize: 0,
        freeBytes: 0,
        activeBytes: 0,
        inactiveBytes: 0,
        wiredBytes: 0,
        compressedBytes: 0,
        purgeableBytes: 0
    )
}
