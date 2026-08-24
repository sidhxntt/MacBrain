import XCTest
@testable import MacBrain

final class DesktopSidebarMetricsTests: XCTestCase {
    func testUsesMinimumWidthForShortChatTitles() {
        XCTAssertEqual(DesktopSidebarMetrics.idealWidth(for: ["Temu"]), 280)
    }

    func testWidensForLongChatTitlesWithoutExceedingMaximum() {
        let longTitle = String(repeating: "Local source research ", count: 8)
        XCTAssertEqual(DesktopSidebarMetrics.idealWidth(for: [longTitle]), 340)
    }

    func testFloatingSidebarUsesItsOwnRoundedPanelWidth() {
        XCTAssertEqual(DesktopSidebarPresentation.minimumWidth, 280)
        XCTAssertEqual(DesktopSidebarPresentation.maximumWidth, 340)
    }
}
