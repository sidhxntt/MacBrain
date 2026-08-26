import Foundation
import Testing
@testable import MacBrain

struct FreshInstallSystemE2ETests {
    @Test("Fresh install answers broad read-only Mac questions through the production responder")
    func broadSystemQuestionsUseFreshTypedFactsWithoutInference() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacBrainFreshSystem-" + UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LocalSourceRepository(
            fileURL: directory.appendingPathComponent("local-sources.json"),
            database: try MacBrainDatabase(url: directory.appendingPathComponent("macbrain.sqlite"))
        )
        try await repository.bootstrap()
        let provider = FreshSystemProviderProbe()
        let liveProvider = FreshSystemLiveProvider(snapshot: Self.snapshot)
        let responder = StreamingChatResponder(
            provider: provider,
            repository: repository,
            selectedModel: { "missing-model" },
            fallback: FreshSystemFallbackResponder(),
            systemProfileProvider: FreshSystemProfileProvider(profile: Self.profile),
            liveContextProvider: liveProvider,
            providerStatusTimeout: .milliseconds(20)
        )
        let cases: [(prompt: String, expected: [String])] = [
            ("How much RAM is installed on this Mac?", ["## Memory now", "Installed: 24 GB", "Swap"]),
            ("How much storage is available right now?", ["## Storage now", "Available: 500 GB", "Macintosh HD"]),
            ("Give me the full specifications of this Mac.", ["## Your Mac", "Apple M5 Pro", "arm64", "macOS 26.0"]),
            ("Which macOS version is installed?", ["## Operating system", "macOS 26.0"]),
            ("How long has this Mac been running?", ["## Uptime now", "2h 0m", "Boot time"]),
            ("What's my battery status?", ["## Power now", "82%", "Cycle count: 200", "Normal"]),
            ("What apps are running right now?", ["## Applications now", "MacBrain", "Finder"]),
            ("How am I connected to the network right now?", ["## Network now", "en0", "intentionally not collected"]),
            ("What displays are connected to this Mac?", ["## Displays now", "Built-in Display", "3024 × 1964"]),
            ("What is the maximum RAM this Mac supports?", ["Installed memory: 24 GB", "macOS does not report a supported maximum"]),
        ]

        for item in cases {
            let response = try await collect(responder.stream(to: item.prompt))
            for expected in item.expected {
                #expect(response.contains(expected), "Missing '\(expected)' for '\(item.prompt)'\n\(response)")
            }
            #expect(response.contains("Captured"))
        }

        #expect(await liveProvider.sampleCount == cases.count)
        #expect(provider.statusCallCount == 0)
        #expect(provider.embeddingCallCount == 0)
        #expect(provider.streamCallCount == 0)
    }

    private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> String {
        var output = ""
        for try await token in stream { output.append(token) }
        return output
    }

    private static let profile = SystemProfile(
        userDisplayName: "Fresh User",
        computerName: "Fresh MacBook Pro",
        hardwareModel: "Mac17,9",
        processor: "Apple M5 Pro",
        memoryBytes: 24_000_000_000,
        operatingSystem: "macOS 26.0 (Build 25A123)",
        totalDiskBytes: 1_000_000_000_000,
        availableDiskBytes: 500_000_000_000,
        localeIdentifier: "en_IN",
        timeZoneIdentifier: "Asia/Kolkata",
        architecture: "arm64",
        physicalCPUCount: 12,
        logicalCPUCount: 12,
        performanceCoreCount: 8,
        efficiencyCoreCount: 4
    )

    private static let snapshot = LiveMacSnapshot(
        capturedAt: Date(timeIntervalSince1970: 1_780_000_000),
        memory: .init(
            pageSize: 16_384,
            freeBytes: 2_000_000_000,
            activeBytes: 10_000_000_000,
            inactiveBytes: 4_000_000_000,
            wiredBytes: 3_000_000_000,
            compressedBytes: 1_000_000_000,
            purgeableBytes: 500_000_000
        ),
        storage: .init(
            totalBytes: 1_000_000_000_000,
            availableBytes: 500_000_000_000,
            volumes: [
                .init(
                    name: "Macintosh HD",
                    totalBytes: 1_000_000_000_000,
                    availableBytes: 500_000_000_000
                )
            ]
        ),
        uptimeSeconds: 7_200,
        cpuLoadAverages: [1.0, 0.8, 0.5],
        power: .init(
            percentage: 82,
            isCharging: true,
            source: "AC Power",
            cycleCount: 200,
            condition: "Normal"
        ),
        activeApplicationName: "MacBrain",
        runningApplicationNames: ["Finder", "MacBrain"],
        networkInterfaces: ["en0"],
        swap: .init(totalBytes: 8_000_000_000, usedBytes: 1_000_000_000),
        bootTime: Date(timeIntervalSince1970: 1_779_992_800),
        displays: [
            .init(
                name: "Built-in Display",
                pixelWidth: 3_024,
                pixelHeight: 1_964,
                scaleFactor: 2,
                isMain: true
            )
        ]
    )
}

private struct FreshSystemProfileProvider: SystemProfileProviding {
    let profile: SystemProfile
    func currentProfile() -> SystemProfile { profile }
}

private actor FreshSystemLiveProvider: LiveMacContextProviding {
    let snapshotValue: LiveMacSnapshot
    private(set) var sampleCount = 0

    init(snapshot: LiveMacSnapshot) {
        snapshotValue = snapshot
    }

    func snapshot(for capabilities: Set<LiveMacCapability>) async -> LiveMacSnapshot {
        sampleCount += 1
        return snapshotValue
    }
}

private final class FreshSystemProviderProbe: InferenceProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var statusCalls = 0
    private var embeddingCalls = 0
    private var streamCalls = 0

    var statusCallCount: Int { lock.withLock { statusCalls } }
    var embeddingCallCount: Int { lock.withLock { embeddingCalls } }
    var streamCallCount: Int { lock.withLock { streamCalls } }

    func status() async -> InferenceProviderStatus {
        lock.withLock { statusCalls += 1 }
        return .runtimeMissing
    }

    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] {
        lock.withLock { embeddingCalls += 1 }
        return []
    }

    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func streamChat(
        model: String,
        messages: [InferenceChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        lock.withLock { streamCalls += 1 }
        return AsyncThrowingStream { continuation in
            continuation.yield("Inference must not run for typed system facts.")
            continuation.finish()
        }
    }
}

private struct FreshSystemFallbackResponder: ChatResponder {
    func respond(to prompt: String) async throws -> String { "Fallback must not run." }
}
