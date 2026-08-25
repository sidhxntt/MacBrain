import AppKit
import Foundation
import os

@MainActor
final class AppCoordinator {
    private let logger = Logger(subsystem: "com.macbrain.app", category: "lifecycle")
    let sourceLibrary: SourceLibraryStore
    let chatStore: ChatStore
    let memoryStore: MemoryStore
    let inferenceStore: InferenceStore
    let workspaceStore = MainWorkspaceStore()
    private(set) var sidebarController: SidebarPanelController?
    private(set) var activationBarController: ActivationBarController?

    init(
        sourceLibrary: SourceLibraryStore = SourceLibraryStore(),
        inferenceStore: InferenceStore? = nil
    ) {
        self.sourceLibrary = sourceLibrary
        let configuredInferenceStore = inferenceStore ?? InferenceStore()
        self.inferenceStore = configuredInferenceStore
        let sessionDatabase = try? MacBrainDatabase()
        let sessionRepository = sessionDatabase.map(LocalChatSessionRepository.init)
        self.memoryStore = MemoryStore(repository: sessionDatabase.map(LocalMemoryRepository.init) ?? UnavailableMemoryRepository())
        let responseCache: any ResponseCaching = (try? MacBrainDatabase()).map(LocalResponseCache.init) ?? InMemoryResponseCache()
        let streamingResponder = StreamingChatResponder(
            provider: configuredInferenceStore.provider,
            repository: sourceLibrary.repository,
            selectedModel: { configuredInferenceStore.selectedChatModel },
            fallback: LocalKnowledgeResponder(repository: sourceLibrary.repository)
        )
        self.chatStore = ChatStore(
            responder: ResponseCachingResponder(
                upstream: streamingResponder,
                cache: responseCache,
                sourceRevisionProvider: sourceLibrary.repository,
                selectedModel: { configuredInferenceStore.selectedChatModel }
            ),
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
            await memoryStore.reload()
            await inferenceStore.refresh()
            await sourceLibrary.processQueuedIndexing(
                using: inferenceStore.provider,
                embeddingModel: inferenceStore.selectedEmbeddingModel
            )
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
