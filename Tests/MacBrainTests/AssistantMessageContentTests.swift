import Foundation
import XCTest

final class AssistantMessageContentTests: XCTestCase {
    func testResponseBlocksDoNotGenerateRandomIdentityDuringViewRendering() throws {
        let source = try String(
            contentsOf: sourceURL("Sources/MacBrain/Views/AssistantMessageContent.swift"),
            encoding: .utf8
        )
        let blockDefinition = try XCTUnwrap(source.range(of: "private struct ChatResponseBlock"))
        let implementation = String(source[blockDefinition.lowerBound...])

        XCTAssertFalse(
            implementation.contains("let id = UUID()"),
            "Response blocks need deterministic identity so SwiftUI does not rebuild the entire answer every layout pass."
        )
    }

    private func sourceURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
    }
}
