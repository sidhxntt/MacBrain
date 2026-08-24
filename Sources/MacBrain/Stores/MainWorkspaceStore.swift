import Combine

@MainActor
final class MainWorkspaceStore: ObservableObject {
    @Published var selection: MainWorkspaceSection = .chats
    @Published private(set) var isSidebarEnabled = false
    @Published private(set) var isNavigationSidebarVisible = true

    func enableSidebar() {
        isSidebarEnabled = true
    }

    func toggleNavigationSidebar() {
        isNavigationSidebarVisible.toggle()
    }

    func setNavigationSidebarVisible(_ isVisible: Bool) {
        isNavigationSidebarVisible = isVisible
    }

}
