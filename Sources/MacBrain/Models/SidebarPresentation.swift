import Foundation

enum SidebarPresentation: Equatable, Sendable {
    case compact
    case expanded

    var preferredWidth: CGFloat {
        switch self {
        case .compact: 360
        case .expanded: 560
        }
    }
}

enum SidebarEdge: Equatable, Sendable {
    case left
    case right
}
