import Foundation
import XCTest

final class DesktopChatSessionTitleTests: XCTestCase {
    func testRecentChatRowsExposeAFullWidthTapTargetAndActiveState() throws {
        let source = try String(contentsOf: sourceURL("Sources/MacBrain/Views/DesktopChatSessionTitle.swift"))

        XCTAssertTrue(source.contains("session.id == chatStore.activeSessionID"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertTrue(source.contains(".contentShape(Rectangle())"))
    }

    func testRecentChatSelectionDoesNotCompeteWithADoubleClickGesture() throws {
        let source = try String(contentsOf: sourceURL("Sources/MacBrain/Views/DesktopChatSessionTitle.swift"))

        XCTAssertFalse(source.contains("TapGesture(count: 2)"))
        XCTAssertTrue(source.contains(".contextMenu"))
    }

    private func sourceURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
    }
}
