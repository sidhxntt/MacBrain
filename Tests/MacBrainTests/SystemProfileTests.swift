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
}
