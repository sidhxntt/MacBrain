import XCTest
@testable import MacBrain

final class LiveMacContextTests: XCTestCase {
    func testLocalProviderReturnsFreshBoundedMacState() async {
        let snapshot = await LocalLiveMacContextProvider().snapshot()

        XCTAssertGreaterThan(snapshot.capturedAt, .distantPast)
        XCTAssertGreaterThan(snapshot.memory.freeBytes, 0)
        XCTAssertGreaterThan(snapshot.storage.totalBytes, 0)
        XCTAssertGreaterThanOrEqual(snapshot.storage.availableBytes, 0)
        XCTAssertGreaterThanOrEqual(snapshot.uptimeSeconds, 0)
        XCTAssertEqual(snapshot.cpuLoadAverages.count, 3)
    }
}
