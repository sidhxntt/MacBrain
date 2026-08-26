import Foundation

struct SystemQueryService: Sendable {
    let systemProfileProvider: any SystemProfileProviding
    let liveContextProvider: any LiveMacContextProviding

    init(
        systemProfileProvider: any SystemProfileProviding = LocalSystemProfileProvider(),
        liveContextProvider: any LiveMacContextProviding = LocalLiveMacContextProvider()
    ) {
        self.systemProfileProvider = systemProfileProvider
        self.liveContextProvider = liveContextProvider
    }

    func response(to prompt: String) async -> String? {
        let plan = LocalQueryPlanner().plan(
            prompt: prompt,
            records: [],
            conversation: []
        )
        guard case .system(let systemPlan) = plan else { return nil }
        return await response(for: systemPlan, prompt: prompt)
    }

    func response(for plan: SystemQueryPlan, prompt: String) async -> String {
        let profile = systemProfileProvider.currentProfile()
        let capabilities = Self.capabilities(for: plan.domains)
        let snapshot = await liveContextProvider.snapshot(for: capabilities)
        var domains = plan.domains
        if domains.contains(.specifications) {
            domains.formUnion([
                .identity, .processor, .memory, .storage, .operatingSystem,
            ])
        }

        var sections: [String] = []
        if domains.contains(.identity) {
            sections.append(identity(profile))
        }
        if domains.contains(.processor) {
            sections.append(processor(profile, snapshot: snapshot))
        }
        if domains.contains(.memory) {
            sections.append(memory(profile, snapshot: snapshot))
        }
        if domains.contains(.storage) {
            sections.append(storage(snapshot.storage))
        }
        if domains.contains(.operatingSystem) {
            sections.append("## Operating system\n\n- \(profile.operatingSystem)")
        }
        if domains.contains(.power) {
            sections.append(power(snapshot.power))
        }
        if domains.contains(.applications) {
            sections.append(applications(snapshot))
        }
        if domains.contains(.network) {
            sections.append(network(snapshot.networkInterfaces))
        }
        if domains.contains(.uptime) {
            sections.append(uptime(snapshot))
        }
        if domains.contains(.displays) {
            sections.append(displays(snapshot.displays))
        }
        if asksForUnsupportedMaximum(prompt) {
            sections.append(
                "## Supported maximum\n\n- Installed memory: \(Self.bytes(Int64(clamping: profile.memoryBytes)))\n- macOS does not report a supported maximum RAM capacity for this Mac. Check the exact model’s official technical specifications for that product limit."
            )
        }
        sections.append("_Captured: \(snapshot.capturedAt.formatted(date: .abbreviated, time: .standard))_\n")
        return sections.joined(separator: "\n\n")
    }

    private static func capabilities(
        for domains: Set<SystemQueryDomain>
    ) -> Set<LiveMacCapability> {
        var capabilities = Set<LiveMacCapability>()
        if domains.contains(.identity) { capabilities.insert(.identity) }
        if domains.contains(.specifications) { capabilities.insert(.specifications) }
        if domains.contains(.memory) { capabilities.formUnion([.memory, .swap]) }
        if domains.contains(.processor) { capabilities.insert(.processor) }
        if domains.contains(.storage) { capabilities.formUnion([.storage, .volumes]) }
        if domains.contains(.operatingSystem) { capabilities.insert(.operatingSystem) }
        if domains.contains(.power) { capabilities.insert(.power) }
        if domains.contains(.applications) { capabilities.insert(.applications) }
        if domains.contains(.network) { capabilities.insert(.network) }
        if domains.contains(.uptime) { capabilities.insert(.uptime) }
        if domains.contains(.displays) { capabilities.insert(.displays) }
        return capabilities
    }

    private func identity(_ profile: SystemProfile) -> String {
        """
        ## Your Mac

        - User: \(profile.userDisplayName)
        - Computer: \(profile.computerName)
        - Model: \(profile.hardwareModel)
        - Architecture: \(profile.architecture)
        """
    }

    private func processor(_ profile: SystemProfile, snapshot: LiveMacSnapshot) -> String {
        var lines = [
            "## Processor now",
            "",
            "- Processor: \(profile.processor)",
            "- Architecture: \(profile.architecture)",
        ]
        let coreCounts = [
            profile.physicalCPUCount.map { "\($0) physical" },
            profile.logicalCPUCount.map { "\($0) logical" },
            profile.performanceCoreCount.map { "\($0) performance" },
            profile.efficiencyCoreCount.map { "\($0) efficiency" },
        ].compactMap { $0 }
        if !coreCounts.isEmpty {
            lines.append("- CPU counts: " + coreCounts.joined(separator: " · "))
        }
        if !snapshot.cpuLoadAverages.isEmpty {
            lines.append(
                "- Load average (1/5/15 min): "
                    + snapshot.cpuLoadAverages.prefix(3)
                        .map { String(format: "%.2f", $0) }
                        .joined(separator: " · ")
            )
        }
        return lines.joined(separator: "\n")
    }

    private func memory(_ profile: SystemProfile, snapshot: LiveMacSnapshot) -> String {
        var lines = [
            "## Memory now",
            "",
            "- Installed: \(Self.bytes(Int64(clamping: profile.memoryBytes)))",
            "- Free now: \(Self.bytes(Int64(clamping: snapshot.memory.freeBytes)))",
            "- Active: \(Self.bytes(Int64(clamping: snapshot.memory.activeBytes)))",
            "- Wired: \(Self.bytes(Int64(clamping: snapshot.memory.wiredBytes)))",
            "- Compressed: \(Self.bytes(Int64(clamping: snapshot.memory.compressedBytes)))",
        ]
        if let swap = snapshot.swap {
            lines.append(
                "- Swap: \(Self.bytes(Int64(clamping: swap.usedBytes))) used of \(Self.bytes(Int64(clamping: swap.totalBytes)))"
            )
        } else {
            lines.append("- Swap: Not reported by macOS")
        }
        return lines.joined(separator: "\n")
    }

    private func storage(_ storage: LiveMacSnapshot.Storage) -> String {
        let used = max(0, storage.totalBytes - storage.availableBytes)
        var lines = [
            "## Storage now",
            "",
            "- Total: \(Self.bytes(storage.totalBytes))",
            "- Used: \(Self.bytes(used))",
            "- Available: \(Self.bytes(storage.availableBytes))",
        ]
        if !storage.volumes.isEmpty {
            lines.append("- Volumes:")
            lines.append(contentsOf: storage.volumes.prefix(12).map { volume in
                "  - \(volume.name): \(Self.bytes(volume.availableBytes)) available of \(Self.bytes(volume.totalBytes))"
            })
        }
        return lines.joined(separator: "\n")
    }

    private func power(_ power: LiveMacSnapshot.Power?) -> String {
        guard let power else { return "## Power now\n\n- No battery is reported by macOS." }
        var lines = [
            "## Power now",
            "",
            "- Battery: \(power.percentage.map { "\($0)%" } ?? "Unknown")",
            "- Charging: \(power.isCharging.map { $0 ? "Yes" : "No" } ?? "Unknown")",
            "- Source: \(power.source ?? "Unknown")",
        ]
        if let cycleCount = power.cycleCount { lines.append("- Cycle count: \(cycleCount)") }
        if let condition = power.condition { lines.append("- Condition: \(condition)") }
        return lines.joined(separator: "\n")
    }

    private func applications(_ snapshot: LiveMacSnapshot) -> String {
        let running = snapshot.runningApplicationNames.prefix(20).joined(separator: ", ")
        return """
        ## Applications now

        - Active: \(snapshot.activeApplicationName ?? "None reported")
        - Running: \(running.isEmpty ? "None reported" : running)
        """
    }

    private func network(_ interfaces: [String]) -> String {
        """
        ## Network now

        - Active interface names: \(interfaces.isEmpty ? "None reported" : interfaces.joined(separator: ", "))
        - Detailed network addressing and wireless identifiers are intentionally not collected.
        """
    }

    private func uptime(_ snapshot: LiveMacSnapshot) -> String {
        let minutes = Int(snapshot.uptimeSeconds) / 60
        let duration = "\(minutes / 1_440)d \((minutes % 1_440) / 60)h \(minutes % 60)m"
        return """
        ## Uptime now

        - Uptime: \(duration)
        - Boot time: \(snapshot.bootTime?.formatted(date: .abbreviated, time: .standard) ?? "Not reported")
        """
    }

    private func displays(_ displays: [LiveMacSnapshot.Display]) -> String {
        guard !displays.isEmpty else { return "## Displays now\n\n- No display details were reported." }
        return "## Displays now\n\n" + displays.prefix(8).map { display in
            "- \(display.name): \(display.pixelWidth) × \(display.pixelHeight) pixels · \(String(format: "%.1f", display.scaleFactor))× scale\(display.isMain ? " · main" : "")"
        }.joined(separator: "\n")
    }

    private func asksForUnsupportedMaximum(_ prompt: String) -> Bool {
        let normalized = SourceVocabulary.normalize(prompt)
        return normalized.containsAnyPhrase(["maximum ram", "max ram", "maximum memory", "memory limit"])
            && normalized.containsAnyPhrase(["support", "supports", "capacity", "maximum", "max", "limit"])
    }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal)
    }
}
