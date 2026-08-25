import XCTest
@testable import MacBrain

final class LiveMacQueryRouterTests: XCTestCase {
    func testRoutesMemoryStorageAppsAndOverviewToFreshLocalResponses() throws {
        let router = LiveMacQueryRouter()
        let snapshot = makeSnapshot()
        let profile = makeProfile()

        XCTAssertTrue(try XCTUnwrap(router.response(to: "How much RAM is free right now?", snapshot: snapshot, profile: profile)).contains("## Memory now"))
        XCTAssertTrue(try XCTUnwrap(router.response(to: "How much disk space is available?", snapshot: snapshot, profile: profile)).contains("## Storage now"))
        XCTAssertTrue(try XCTUnwrap(router.response(to: "Which apps are running?", snapshot: snapshot, profile: profile)).contains("## Apps now"))
        XCTAssertTrue(try XCTUnwrap(router.response(to: "Give me a current Mac status overview", snapshot: snapshot, profile: profile)).contains("## Mac status now"))
    }

    func testDoesNotRouteWorkKnowledgeQuestionAsLiveMacState() {
        XCTAssertNil(LiveMacQueryRouter().response(to: "What did I decide about the release?", snapshot: makeSnapshot(), profile: makeProfile()))
    }

    private func makeSnapshot() -> LiveMacSnapshot {
        .init(
            capturedAt: .now,
            memory: .init(pageSize: 16_384, freeBytes: 2_000_000_000, activeBytes: 10_000_000_000, inactiveBytes: 4_000_000_000, wiredBytes: 3_000_000_000, compressedBytes: 1_000_000_000, purgeableBytes: 500_000_000),
            storage: .init(totalBytes: 1_000_000_000_000, availableBytes: 512_000_000_000),
            uptimeSeconds: 7_200,
            cpuLoadAverages: [1.2, 0.8, 0.6],
            power: .init(percentage: 82, isCharging: true, source: "AC Power"),
            activeApplicationName: "MacBrain",
            runningApplicationNames: ["Finder", "MacBrain"],
            networkInterfaces: ["en0"]
        )
    }

    private func makeProfile() -> SystemProfile {
        .init(userDisplayName: "Siddhant Gupta", computerName: "Siddhant’s MacBook Pro", hardwareModel: "Mac17,9", processor: "Apple M5 Pro", memoryBytes: 24_000_000_000, operatingSystem: "macOS 26.6.2", totalDiskBytes: 1_000_000_000_000, availableDiskBytes: 512_000_000_000, localeIdentifier: "en_IN", timeZoneIdentifier: "Asia/Kolkata")
    }
}
