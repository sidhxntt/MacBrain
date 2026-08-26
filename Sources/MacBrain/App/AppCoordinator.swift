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
    let contextSafeguards = ContextSafeguards()
    let workspaceStore = MainWorkspaceStore()
    private(set) var sidebarController: SidebarPanelController?
    private(set) var activationBarController: ActivationBarController?

    init(
        sourceLibrary: SourceLibraryStore? = nil,
        inferenceStore: InferenceStore? = nil
    ) {
        let sessionDatabase = try? MacBrainDatabase()
        self.sourceLibrary = sourceLibrary ?? SourceLibraryStore(
            repository: LocalSourceRepository(database: sessionDatabase),
            database: sessionDatabase
        )
        let configuredInferenceStore = inferenceStore ?? InferenceStore()
        self.inferenceStore = configuredInferenceStore
        let sessionRepository = sessionDatabase.map(LocalChatSessionRepository.init)
        self.memoryStore = MemoryStore(repository: sessionDatabase.map(LocalMemoryRepository.init) ?? UnavailableMemoryRepository())
        let responseCache: any ResponseCaching = sessionDatabase.map(LocalResponseCache.init) ?? InMemoryResponseCache()
        let streamingResponder = StreamingChatResponder(
            provider: configuredInferenceStore.provider,
            repository: self.sourceLibrary.repository,
            selectedModel: { configuredInferenceStore.selectedChatModel },
            selectedEmbeddingModel: { configuredInferenceStore.selectedEmbeddingModel },
            fallback: LocalKnowledgeResponder(repository: self.sourceLibrary.repository)
        )
        self.chatStore = ChatStore(
            responder: ResponseCachingResponder(
                upstream: streamingResponder,
                cache: responseCache,
                sourceRevisionProvider: self.sourceLibrary.repository,
                selectedModel: { configuredInferenceStore.selectedChatModel }
            ),
            sessionRepository: sessionRepository,
            contextSafeguards: contextSafeguards
        )
    }

    func start() {
        logger.info("Application launched")
        sourceLibrary.configureAutomaticIndexing(
            using: inferenceStore.provider,
            selectedEmbeddingModel: { [inferenceStore] in inferenceStore.selectedEmbeddingModel }
        )
        let sidebar = SidebarPanelController(
            sourceLibrary: sourceLibrary,
            chatStore: chatStore,
            contextSafeguards: contextSafeguards
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
            await sourceLibrary.reload()
            await chatStore.restorePersistedSessions()
            await memoryStore.reload()
            await inferenceStore.refresh()
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
