import Foundation

enum ActivationBarInteraction {
    enum Action: Equatable {
        case activate
        case drag
    }

    static func action(forVerticalDrag distance: CGFloat) -> Action {
        abs(distance) < 3 ? .activate : .drag
    }
}
