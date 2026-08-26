import SwiftUI

struct MacBrainWorkspaceView: View {
    static let showsCustomSidebarToggle = false

    let coordinator: AppCoordinator
    @ObservedObject private var workspaceStore: MainWorkspaceStore
    @ObservedObject private var chatStore: ChatStore
    @ObservedObject private var sourceLibrary: SourceLibraryStore
    @ObservedObject private var onboardingStore: OnboardingStore

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        _workspaceStore = ObservedObject(wrappedValue: coordinator.workspaceStore)
        _chatStore = ObservedObject(wrappedValue: coordinator.chatStore)
        _sourceLibrary = ObservedObject(wrappedValue: coordinator.sourceLibrary)
        _onboardingStore = ObservedObject(wrappedValue: coordinator.onboardingStore)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: navigationSidebarVisibility) {
            MacBrainWorkspaceSidebar(
                selection: $workspaceStore.selection,
                chatStore: chatStore
            )
            .navigationSplitViewColumnWidth(
                min: DesktopSidebarPresentation.minimumWidth,
                ideal: DesktopSidebarMetrics.idealWidth(for: chatStore.openSessions.map(\.title)),
                max: DesktopSidebarPresentation.maximumWidth
            )
        } detail: {
            NavigationStack {
                detail
                    .toolbar {
                        toolbarContent
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: onboardingPresentation) {
            MacBrainOnboardingView(
                store: onboardingStore,
                sourceLibrary: sourceLibrary,
                inferenceStore: coordinator.inferenceStore
            )
            .interactiveDismissDisabled()
        }
    }

    private var onboardingPresentation: Binding<Bool> {
        Binding(
            get: { onboardingStore.isPresented },
            set: { _ in
                // Setup closes only through Finish or the explicit limited-context
                // action, both of which persist an intentional completion mode.
            }
        )
    }

    private var navigationSidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { workspaceStore.isNavigationSidebarVisible ? .all : .detailOnly },
            set: { visibility in
                workspaceStore.setNavigationSidebarVisible(visibility != .detailOnly)
            }
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Open Sidebar", systemImage: "rectangle.righthalf.inset.filled") {
                coordinator.openSidebar()
            }
            .help("Open MacBrain sidebar")

            Button("New Chat", systemImage: "plus") {
                workspaceStore.selection = .chats
                chatStore.startNewChat()
            }
            .help("New chat")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch workspaceStore.selection {
        case .chats:
            MacBrainChatWorkspaceView(chatStore: chatStore, sourceLibrary: sourceLibrary)
        case .sources:
            MacBrainSourcesWorkspaceView(sourceLibrary: sourceLibrary)
        case .preferences:
            MacBrainPreferencesView(coordinator: coordinator)
        }
    }
}
