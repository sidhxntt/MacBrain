import Foundation
import XCTest
@testable import MacBrain

final class SystemQueryServiceTests: XCTestCase {
    func testSupportedDomainsRenderTypedFreshFacts() async {
        let fixture = makeFixture()
        let plan = SystemQueryPlan(
            domains: Set(SystemQueryDomain.allCases),
            responseStyle: .synthesizedOverview
        )

        let response = await fixture.service.response(
            for: plan,
            prompt: "Show all specifications and current system status"
        )

        XCTAssertTrue(response.contains("Test Mac"))
        XCTAssertTrue(response.contains("arm64"))
        XCTAssertTrue(response.contains("Apple M5 Pro"))
        XCTAssertTrue(response.contains("12 physical"))
        XCTAssertTrue(response.contains("12 logical"))
        XCTAssertTrue(response.contains("8 performance"))
        XCTAssertTrue(response.contains("4 efficiency"))
        XCTAssertTrue(response.contains("24 GB"))
        XCTAssertTrue(response.contains("Swap"))
        XCTAssertTrue(response.contains("macOS 26.0"))
        XCTAssertTrue(response.contains("Macintosh HD"))
        XCTAssertTrue(response.contains("82%"))
        XCTAssertTrue(response.contains("Finder"))
        XCTAssertTrue(response.contains("en0"))
        XCTAssertTrue(response.contains("Built-in Display"))
        XCTAssertTrue(response.contains("3024 × 1964"))
        XCTAssertTrue(response.contains("Boot time"))
        XCTAssertTrue(response.contains("Captured"))
        XCTAssertFalse(response.localizedCaseInsensitiveContains("serial number"))
        XCTAssertFalse(response.localizedCaseInsensitiveContains("ip address"))
    }

    func testMaximumSpecificationNeverInventsAProductLimit() async {
        let fixture = makeFixture()
        let response = await fixture.service.response(
            for: SystemQueryPlan(domains: [.memory], responseStyle: .direct),
            prompt: "What is the maximum RAM this Mac supports?"
        )

        XCTAssertTrue(response.contains("Installed memory: 24 GB"))
        XCTAssertTrue(response.contains("macOS does not report a supported maximum"))
    }

    func testDynamicStorageSamplesEveryRequest() async {
        let fixture = makeFixture()
        let plan = SystemQueryPlan(domains: [.storage], responseStyle: .direct)

        _ = await fixture.service.response(for: plan, prompt: "How much storage is available?")
        _ = await fixture.service.response(for: plan, prompt: "What storage is free now?")

        let sampleCount = await fixture.liveProvider.sampleCount
        XCTAssertEqual(sampleCount, 2)
    }

    func testPromptConvenienceUsesSameTypedPlanner() async {
        let fixture = makeFixture()

        let response = await fixture.service.response(
            to: "What are this Mac's processor, RAM, and storage specifications?"
        )

        XCTAssertNotNil(response)
        XCTAssertTrue(response?.contains("Apple M5 Pro") == true)
        XCTAssertTrue(response?.contains("24 GB") == true)
    }

    private func makeFixture() -> SystemQueryFixture {
        let capturedAt = Date(timeIntervalSince1970: 1_780_000_000)
        let profile = SystemProfile(
            userDisplayName: "Test User",
            computerName: "Test Mac",
            hardwareModel: "Mac17,9",
            processor: "Apple M5 Pro",
            memoryBytes: 24_000_000_000,
            operatingSystem: "macOS 26.0",
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
        let snapshot = LiveMacSnapshot(
            capturedAt: capturedAt,
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
            bootTime: capturedAt.addingTimeInterval(-7_200),
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
        let liveProvider = CountingSystemLiveProvider(snapshot: snapshot)
        return SystemQueryFixture(
            service: SystemQueryService(
                systemProfileProvider: FixedSystemQueryProfileProvider(profile: profile),
                liveContextProvider: liveProvider
            ),
            liveProvider: liveProvider
        )
    }
}

private struct SystemQueryFixture {
    let service: SystemQueryService
    let liveProvider: CountingSystemLiveProvider
}

private struct FixedSystemQueryProfileProvider: SystemProfileProviding {
    let profile: SystemProfile
    func currentProfile() -> SystemProfile { profile }
}

private actor CountingSystemLiveProvider: LiveMacContextProviding {
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
