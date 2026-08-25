import AppKit
import Foundation
import os

@MainActor
final class AppCoordinator {
    private let logger = Logger(subsystem: "com.macbrain.app", category: "lifecycle")
    let sourceLibrary: SourceLibraryStore
    let chatStore: ChatStore
    let workspaceStore = MainWorkspaceStore()
    private(set) var sidebarController: SidebarPanelController?
    private(set) var activationBarController: ActivationBarController?

    init(sourceLibrary: SourceLibraryStore = SourceLibraryStore()) {
        self.sourceLibrary = sourceLibrary
        let sessionRepository = (try? MacBrainDatabase()).map(LocalChatSessionRepository.init)
        self.chatStore = ChatStore(
            responder: LocalKnowledgeResponder(repository: sourceLibrary.repository),
            sessionRepository: sessionRepository
        )
    }

    func start() {
        logger.info("Application launched")
        let sidebar = SidebarPanelController(
            sourceLibrary: sourceLibrary,
            chatStore: chatStore
        )
        let activationBar = ActivationBarController { [weak self] in
            self?.openSidebar()
        }

        sidebar.onHide = { [weak self, weak activationBar] in
            guard self?.workspaceStore.isSidebarEnabled == true else { return }
            activationBar?.show()
        }
        sidebarController = sidebar
        activationBarController = activationBar
        Task { @MainActor [sourceLibrary] in
            await Task.yield()
            NSApp.activate(ignoringOtherApps: true)
            await sourceLibrary.reload()
            await chatStore.restorePersistedSessions()
            sourceLibrary.startAutomaticRefresh()
        }
    }

    func stop() {
        sourceLibrary.stopAutomaticRefresh()
        activationBarController?.hide()
        sidebarController?.hide(notify: false)
        logger.info("Application stopped")
    }

    func openSidebar() {
        workspaceStore.enableSidebar()
        activationBarController?.hide()
        sidebarController?.focus()
    }
}
