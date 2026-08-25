import XCTest
@testable import MacBrain

final class AdaptiveGlassRoleTests: XCTestCase {
    func testShellUsesQuietNoninteractiveTreatment() {
        XCTAssertFalse(AdaptiveGlassRole.shell.isInteractive)
        XCTAssertFalse(AdaptiveGlassRole.shell.usesSemanticTint)
        XCTAssertEqual(AdaptiveGlassRole.shell.outlineOpacity, 0.18)
        XCTAssertEqual(AdaptiveGlassRole.shell.shadowRadius, 18)
    }

    func testComposerUsesInteractiveTreatmentWithoutTint() {
        XCTAssertTrue(AdaptiveGlassRole.composer.isInteractive)
        XCTAssertFalse(AdaptiveGlassRole.composer.usesSemanticTint)
        XCTAssertEqual(AdaptiveGlassRole.composer.outlineOpacity, 0.16)
    }

    func testMessageRolesRemainVisuallyDistinct() {
        XCTAssertFalse(AdaptiveGlassRole.assistantMessage.usesSemanticTint)
        XCTAssertTrue(AdaptiveGlassRole.userMessage.usesSemanticTint)
        XCTAssertGreaterThan(
            AdaptiveGlassRole.userMessage.fallbackTintOpacity,
            AdaptiveGlassRole.assistantMessage.fallbackTintOpacity
        )
    }

    func testProminentActionIsInteractiveAndNeutral() {
        XCTAssertTrue(AdaptiveGlassRole.prominentAction.isInteractive)
        XCTAssertFalse(AdaptiveGlassRole.prominentAction.usesSemanticTint)
        XCTAssertEqual(AdaptiveGlassRole.prominentAction.shadowRadius, 4)
    }
}
