import XCTest
@testable import MacBrain

final class SystemProfileTests: XCTestCase {
    func testPromptContextIncludesUsefulLocalMachineAndAccountFacts() {
        let profile = SystemProfile(
            userDisplayName: "Siddhant Gupta",
            computerName: "Siddhant’s MacBook Pro",
            hardwareModel: "Mac16,7",
            processor: "Apple M5 Pro",
            memoryBytes: 24_000_000_000,
            operatingSystem: "macOS 26.0 (Build 25A123)",
            totalDiskBytes: 1_000_000_000_000,
            availableDiskBytes: 512_000_000_000,
            localeIdentifier: "en_IN",
            timeZoneIdentifier: "Asia/Kolkata"
        )

        let context = profile.promptContext

        XCTAssertTrue(context.contains("Siddhant Gupta"))
        XCTAssertTrue(context.contains("Apple M5 Pro"))
        XCTAssertTrue(context.contains("24 GB"))
        XCTAssertTrue(context.contains("macOS 26.0"))
        XCTAssertTrue(context.contains("Asia/Kolkata"))
        XCTAssertFalse(context.localizedCaseInsensitiveContains("serial"))
        XCTAssertFalse(context.localizedCaseInsensitiveContains("password"))
    }

    func testLiveMemoryBreakdownUsesCurrentCountersWithoutMarkdownSourceSyntax() throws {
        let usage = SystemMemoryUsage(
            pageSize: 16_384,
            freeBytes: 2_000_000_000,
            activeBytes: 10_000_000_000,
            inactiveBytes: 4_000_000_000,
            wiredBytes: 3_000_000_000,
            compressedBytes: 1_000_000_000,
            purgeableBytes: 500_000_000
        )
        let profile = SystemProfile(
            userDisplayName: "Siddhant Gupta",
            computerName: "Siddhant’s MacBook Pro",
            hardwareModel: "Mac17,9",
            processor: "Apple M5 Pro",
            memoryBytes: 24_000_000_000,
            operatingSystem: "macOS 26.6.2",
            totalDiskBytes: 1_000_000_000_000,
            availableDiskBytes: 512_000_000_000,
            localeIdentifier: "en_IN",
            timeZoneIdentifier: "Asia/Kolkata",
            memoryUsage: usage
        )

        let response = try XCTUnwrap(profile.liveMemoryResponse)

        XCTAssertTrue(response.contains("## Memory now"))
        XCTAssertTrue(response.contains("Free now"))
        XCTAssertTrue(response.contains("Reclaimable estimate"))
        XCTAssertTrue(response.contains("Active"))
        XCTAssertTrue(response.contains("Wired"))
        XCTAssertFalse(response.contains("**"))
    }
}
