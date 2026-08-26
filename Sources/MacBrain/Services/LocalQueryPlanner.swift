import Foundation

struct LocalQueryPlanner: Sendable {
    func plan(
        prompt: String,
        records: [ConnectorRecord],
        conversation: [ChatMessage]
    ) -> LocalQueryPlan {
        if let response = PrivacyPromptPolicy.response(for: prompt) {
            return .restricted(response: response)
        }

        let normalized = SourceVocabulary.normalize(prompt)
        if Self.casualPrompts.contains(normalized.text) {
            return .casual
        }
        if let systemPlan = systemPlan(for: normalized) {
            return .system(systemPlan)
        }

        var scope = SourceVocabulary(records: records).scope(in: prompt)
        if scope == nil {
            scope = SourceVocabulary.firstPersonCountScope(in: normalized)
        }
        if isConnectorCapabilityQuestion(normalized), let scope {
            return .connectorCapability(scope: scope)
        }
        if let operation = connectorOperation(for: normalized, scope: scope) {
            return .connector(operation, scope: scope)
        }
        if isPublicSourceConcept(normalized) {
            scope = nil
        }
        if explicitlyDisablesLocalSources(normalized) {
            return .casual
        }

        // Grounded follow-ups and ordinary content questions share the same
        // lexical-first evidence path. Acceptance later decides whether local
        // evidence is strong enough to influence the answer.
        return .evidenceSearch(scope: scope)
    }

    func shouldInheritGroundedEvidence(
        prompt: String,
        conversation: [ChatMessage]
    ) -> Bool {
        isGroundedFollowUp(
            SourceVocabulary.normalize(prompt),
            conversation: conversation
        )
    }

    private func connectorOperation(
        for prompt: NormalizedSourcePrompt,
        scope: Set<SourceConnectorKind>?
    ) -> ConnectorQueryOperation? {
        let hasCountIntent = prompt.containsAnyPhrase([
            "how many", "total number", "number of", "count", "item count"
        ])
        if hasCountIntent, scope != nil || prompt.containsAnyPhrase(["connected sources", "indexed items"]) {
            return .count
        }
        if scope?.contains(.calendar) == true,
           prompt.containsAnyPhrase([
               "next event", "next calendar event", "next meeting", "next calendar meeting",
               "upcoming event", "upcoming calendar event", "upcoming meeting"
           ]) {
            return .nextEvent
        }
        if scope?.contains(.reminders) == true,
           prompt.containsAnyPhrase(["first due", "next reminder", "due reminder", "earliest reminder"]) {
            return .firstDueReminder
        }
        if scope != nil, prompt.containsAnyPhrase(["newest", "latest", "most recent"]) {
            return .newest(limit: requestedLimit(in: prompt) ?? 1)
        }
        if scope != nil, prompt.containsAnyPhrase(["oldest", "earliest", "first added"]) {
            return .oldest(limit: requestedLimit(in: prompt) ?? 1)
        }
        return nil
    }

    private func requestedLimit(in prompt: NormalizedSourcePrompt) -> Int? {
        prompt.tokens.compactMap(Int.init).first.map { min(max($0, 1), 20) }
    }

    private func systemPlan(for prompt: NormalizedSourcePrompt) -> SystemQueryPlan? {
        let personalSignal = prompt.containsAnyPhrase([
            "my mac", "this mac", "on my mac", "mac s", "installed", "right now",
            "currently", "current system", "system overview", "system specifications",
            "who am i", "tell me who i am"
        ])
        let quantitativeSignal = prompt.containsAnyPhrase([
            "how much ram", "how much memory", "how much storage", "how much disk",
            "ram usage", "current ram", "memory usage", "swap usage", "disk space",
            "storage space", "cpu load",
            "mac uptime", "battery status", "network interfaces", "macos version",
            "what mac model", "which mac model", "apps are running", "applications are running",
            "been running", "running since", "last boot"
        ])
        guard personalSignal || quantitativeSignal else { return nil }

        var domains = Set<SystemQueryDomain>()
        if prompt.containsAnyPhrase(["who am i", "computer name", "mac model", "hardware model"]) {
            domains.insert(.identity)
        }
        if prompt.containsAnyPhrase(["specification", "specifications", "specs", "system overview", "about this mac"]) {
            domains.insert(.specifications)
        }
        if prompt.containsAnyPhrase(["ram", "memory", "swap"]) {
            domains.insert(.memory)
        }
        if prompt.containsAnyPhrase(["cpu", "processor", "chip", "cores"]) {
            domains.insert(.processor)
        }
        if prompt.containsAnyPhrase(["storage", "disk", "volume", "space available", "free space"]) {
            domains.insert(.storage)
        }
        if prompt.containsAnyPhrase(["macos", "operating system", "os version"]) {
            domains.insert(.operatingSystem)
        }
        if prompt.containsAnyPhrase(["battery", "charging", "power"]) {
            domains.insert(.power)
        }
        if prompt.containsAnyPhrase(["running apps", "apps are running", "applications", "active app", "application is active"]) {
            domains.insert(.applications)
        }
        if prompt.containsAnyPhrase(["network", "interfaces", "wifi", "wi fi"]) {
            domains.insert(.network)
        }
        if prompt.containsAnyPhrase([
            "uptime", "boot time", "started up", "been running", "running since", "last boot"
        ]) {
            domains.insert(.uptime)
        }
        if prompt.containsAnyPhrase(["display", "displays", "monitor", "screen resolution"]) {
            domains.insert(.displays)
        }

        if domains.contains(.specifications) {
            if prompt.containsAnyPhrase(["ram", "memory"]) { domains.insert(.memory) }
            if prompt.containsAnyPhrase(["processor", "cpu", "chip"]) { domains.insert(.processor) }
            if prompt.containsAnyPhrase(["storage", "disk"]) { domains.insert(.storage) }
            if prompt.containsAnyPhrase(["macos", "operating system"]) { domains.insert(.operatingSystem) }
        }
        guard !domains.isEmpty else { return nil }
        return SystemQueryPlan(
            domains: domains,
            responseStyle: domains.count > 1 || domains.contains(.specifications)
                ? .synthesizedOverview
                : .direct
        )
    }

    private func isConnectorCapabilityQuestion(_ prompt: NormalizedSourcePrompt) -> Bool {
        guard prompt.text.hasPrefix("can you read")
                || prompt.text.hasPrefix("can you access")
                || prompt.text.hasPrefix("do you have access")
                || prompt.text.hasPrefix("are my")
                || prompt.text.hasPrefix("is my") else {
            return false
        }
        return !prompt.containsAnyPhrase([
            "search", "find", "summarize", "show", "about", "tell me about", "what", "who",
            "when", "where", "why", "how"
        ])
    }

    private func explicitlyDisablesLocalSources(_ prompt: NormalizedSourcePrompt) -> Bool {
        prompt.containsAnyPhrase([
            "ignore local sources", "without local sources", "do not use local sources",
            "don t use local sources", "use no local sources"
        ])
    }

    private func isPublicSourceConcept(_ prompt: NormalizedSourcePrompt) -> Bool {
        let publicPrefix = [
            "what is ", "what are ", "who is ", "who are ", "how does", "how do",
            "explain", "define", "teach me", "write code"
        ].contains { prompt.text.hasPrefix($0) }
        guard publicPrefix else { return false }
        return !prompt.containsAnyPhrase([
            "my", "our", "connected", "local", "indexed", "this repo", "this file",
            "this folder", "search", "find", "according to"
        ])
    }

    private func isGroundedFollowUp(
        _ prompt: NormalizedSourcePrompt,
        conversation: [ChatMessage]
    ) -> Bool {
        guard prompt.tokens.count <= 12,
              let previousAssistant = conversation.last(where: { $0.role == .assistant }),
              !previousAssistant.groundingSourceIDs.isEmpty else {
            return false
        }
        return prompt.containsAnyPhrase([
            "that", "those", "it", "them", "tell me more", "what about", "why",
            "when", "who", "where", "how"
        ])
    }

    private static let casualPrompts: Set<String> = [
        "hello", "hi", "hey", "what s up", "how are you", "how s it going",
        "good morning", "good afternoon", "good evening", "thanks", "thank you",
        "nice to meet you", "okay", "got it", "cool", "whats up", "thx", "ok",
        "hello there", "hey there"
    ]
}
