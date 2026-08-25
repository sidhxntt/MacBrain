import Foundation

enum MainWorkspaceSection: Hashable, CaseIterable, Identifiable {
    case chats
    case sources
    case preferences

    var id: Self { self }

    static let primarySidebarItems: [Self] = [.chats, .sources]

    var title: String {
        switch self {
        case .chats: "Chats"
        case .sources: "Sources"
        case .preferences: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .chats: "bubble.left.and.bubble.right"
        case .sources: "externaldrive"
        case .preferences: "gearshape"
        }
    }
}
