import XCTest
@testable import MacBrain

final class ActivationBarInteractionTests: XCTestCase {
    func testShortPressIsAnActivation() {
        XCTAssertEqual(ActivationBarInteraction.action(forVerticalDrag: 0), .activate)
        XCTAssertEqual(ActivationBarInteraction.action(forVerticalDrag: 2), .activate)
    }

    func testMouseDragIsNotAnActivation() {
        XCTAssertEqual(ActivationBarInteraction.action(forVerticalDrag: 3), .drag)
        XCTAssertEqual(ActivationBarInteraction.action(forVerticalDrag: -18), .drag)
    }
}
