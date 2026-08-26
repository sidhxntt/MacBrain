import Foundation

struct LiveMacQueryRouter {
    func capabilities(for prompt: String) -> Set<LiveMacCapability> {
        let normalized = prompt.lowercased()
        var capabilities = Set<LiveMacCapability>()

        if normalized.contains("who am i") || normalized.contains("computer name") || normalized.contains("mac model") {
            capabilities.insert(.identity)
        }
        if normalized.contains("specification") || normalized.contains("about this mac") {
            capabilities.insert(.specifications)
        }
        if normalized.contains("ram") || normalized.contains("memory") || normalized.contains("swap") {
            capabilities.insert(.memory)
        }
        if normalized.contains("swap") { capabilities.insert(.swap) }
        if normalized.contains("cpu") || normalized.contains("processor") || normalized.contains("load average") {
            capabilities.insert(.processor)
        }
        if normalized.contains("disk") || normalized.contains("storage") || normalized.contains("drive") || normalized.contains("space available") {
            capabilities.insert(.storage)
        }
        if normalized.contains("volume") { capabilities.insert(.volumes) }
        if normalized.contains("macos") || normalized.contains("operating system") || normalized.contains("os version") {
            capabilities.insert(.operatingSystem)
        }
        if normalized.contains("battery") || normalized.contains("charging") || normalized.contains("power") {
            capabilities.insert(.power)
        }
        if normalized.contains("wifi") || normalized.contains("wi-fi") || normalized.contains("network") || normalized.contains("internet") || normalized.contains("connectivity") {
            capabilities.insert(.network)
        }
        if normalized.contains("running app")
            || normalized.contains("running application")
            || normalized.contains("active app")
            || normalized.contains("active application")
            || normalized.contains("running process")
            || (normalized.contains("apps") && normalized.contains("running"))
            || (normalized.contains("applications") && normalized.contains("running"))
        {
            capabilities.insert(.applications)
        }
        if normalized.contains("uptime") || normalized.contains("booted") || normalized.contains("running since") {
            capabilities.insert(.uptime)
        }
        if normalized.contains("display") || normalized.contains("monitor") || normalized.contains("screen resolution") {
            capabilities.insert(.displays)
        }
        if normalized.contains("mac status") || normalized.contains("system overview") || normalized.contains("system health") || normalized.contains("current mac") {
            capabilities.formUnion(LiveMacCapability.allCases)
        }
        return capabilities
    }

    func response(to prompt: String, snapshot: LiveMacSnapshot, profile: SystemProfile) -> String? {
        let capabilities = capabilities(for: prompt)
        return response(for: capabilities, snapshot: snapshot, profile: profile)
    }

    func response(
        for capabilities: Set<LiveMacCapability>,
        snapshot: LiveMacSnapshot,
        profile: SystemProfile
    ) -> String? {
        guard !capabilities.isEmpty else { return nil }

        if capabilities.count == 1, let capability = capabilities.first {
            return response(for: capability, snapshot: snapshot, profile: profile)
        }

        return overview(snapshot: snapshot, profile: profile, capabilities: capabilities)
    }

    private func response(for capability: LiveMacCapability, snapshot: LiveMacSnapshot, profile: SystemProfile) -> String {
        switch capability {
        case .identity, .specifications:
            return profile.markdownSummary
        case .memory:
            return snapshot.memory.markdownBreakdown(totalMemoryBytes: profile.memoryBytes)
        case .swap:
            guard let swap = snapshot.swap else {
                return "## Swap now\n\n- Swap counters were not reported by macOS."
            }
            return "## Swap now\n\n- Used: \(byteCount(Int64(clamping: swap.usedBytes)))\n- Total: \(byteCount(Int64(clamping: swap.totalBytes)))"
        case .processor:
            return """
            ## CPU now

            - Load average: \(loadAverages(snapshot.cpuLoadAverages))
            - Processor: \(profile.processor)

            Load average reflects runnable work over the last 1, 5, and 15 minutes; it is not a CPU-percentage reading.
            """
        case .storage:
            let used = max(0, snapshot.storage.totalBytes - snapshot.storage.availableBytes)
            return """
            ## Storage now

            - Total: \(byteCount(snapshot.storage.totalBytes))
            - Used: \(byteCount(used))
            - Available: \(byteCount(snapshot.storage.availableBytes))
            """
        case .volumes:
            guard !snapshot.storage.volumes.isEmpty else {
                return "## Volumes now\n\n- No mounted volume capacities were reported."
            }
            return "## Volumes now\n\n" + snapshot.storage.volumes.prefix(12).map { volume in
                "- \(volume.name): \(byteCount(volume.availableBytes)) available of \(byteCount(volume.totalBytes))"
            }.joined(separator: "\n")
        case .operatingSystem:
            return "## Operating system\n\n- \(profile.operatingSystem)"
        case .power:
            guard let power = snapshot.power else {
                return "## Power now\n\nNo battery is currently reported by macOS."
            }
            let percentage = power.percentage.map { "\($0)%" } ?? "Unknown"
            let charging = power.isCharging.map { $0 ? "Charging" : "Not charging" } ?? "Charging state unavailable"
            return """
            ## Power now

            - Battery: \(percentage)
            - State: \(charging)
            - Source: \(power.source ?? "Unknown")
            """
        case .network:
            let interfaces = snapshot.networkInterfaces.isEmpty ? "No active non-loopback interface reported" : snapshot.networkInterfaces.joined(separator: ", ")
            return """
            ## Network now

            - Active interfaces: \(interfaces)
            """
        case .applications:
            let active = snapshot.activeApplicationName ?? "No active app reported"
            let running = snapshot.runningApplicationNames.prefix(12).joined(separator: ", ")
            return """
            ## Apps now

            - Active app: \(active)
            - Running apps: \(running.isEmpty ? "None reported" : running)
            """
        case .uptime:
            return "## Uptime now\n\n- Uptime: \(uptime(snapshot.uptimeSeconds))"
        case .displays:
            guard !snapshot.displays.isEmpty else {
                return "## Displays now\n\n- No display details were reported."
            }
            return "## Displays now\n\n" + snapshot.displays.prefix(8).map { display in
                "- \(display.name): \(display.pixelWidth) × \(display.pixelHeight) pixels"
            }.joined(separator: "\n")
        }
    }

    private func overview(snapshot: LiveMacSnapshot, profile: SystemProfile, capabilities: Set<LiveMacCapability>) -> String {
        var sections = ["## Mac status now"]
        for capability in LiveMacCapability.allCases where capabilities.contains(capability) {
            let section = response(for: capability, snapshot: snapshot, profile: profile)
                .replacingOccurrences(of: "## ", with: "### ")
            sections.append(section)
        }
        return sections.joined(separator: "\n\n")
    }

    private func loadAverages(_ values: [Double]) -> String {
        let labels = ["1 min", "5 min", "15 min"]
        return zip(labels, values).map { "\($0): \(String(format: "%.2f", $1))" }.joined(separator: " · ")
    }

    private func uptime(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds) / 60
        return "\(totalMinutes / 1_440)d \((totalMinutes % 1_440) / 60)h \(totalMinutes % 60)m"
    }

    private func byteCount(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal)
    }
}
