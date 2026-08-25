import Combine
import Foundation

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var openSessions: [ChatSession]
    @Published private(set) var archivedSessions: [ChatSession] = []
    @Published private(set) var pinnedSessionIDs: Set<UUID> = []
    @Published private(set) var activeSessionID: UUID
    @Published private(set) var currentTitle = "Untitled"
    @Published private(set) var welcomeGreeting: String
    @Published var draft = ""
    @Published private(set) var isSending = false

    private let responder: any ChatResponder
    private let greetingProvider: () -> String
    private let sessionRepository: (any ChatSessionPersisting)?
    private let responseTimeout: Duration
    private var sendingTask: Task<Void, Never>?
    private var sendingTaskID: UUID?
    private var activeResponseID: UUID?
    private var activeAssistantMessageID: UUID?
    private var responseWatchdogTask: Task<Void, Never>?
    private var watchdogResponseID: UUID?
    private var immediatePersistenceTask: Task<Void, Never>?
    private var deferredPersistenceTask: Task<Void, Never>?

    init(
        responder: any ChatResponder = LocalMockChatResponder(),
        greetingProvider: @escaping () -> String = { MacBrainGreeting.random() },
        sessionRepository: (any ChatSessionPersisting)? = nil,
        responseTimeout: Duration = .seconds(45)
    ) {
        let initialGreeting = greetingProvider()
        let initialSession = ChatSession(messages: [], greeting: initialGreeting)
        self.responder = responder
        self.greetingProvider = greetingProvider
        self.sessionRepository = sessionRepository
        self.responseTimeout = responseTimeout
        self.openSessions = [initialSession]
        self.activeSessionID = initialSession.id
        self.welcomeGreeting = initialGreeting
    }

    func sendDraft() async {
        guard !isSending else { return }

        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        draft = ""
        if currentTitle == "Untitled" {
            currentTitle = ChatTitleGenerator.title(for: prompt)
        }
        let conversation = messages
        messages.append(ChatMessage(role: .user, text: prompt))
        synchronizeCurrentSession()
        let responseID = UUID()
        activeResponseID = responseID
        activeAssistantMessageID = nil
        isSending = true
        armResponseWatchdog(for: responseID)
        defer {
            finishResponseIfActive(responseID)
        }

        var streamedText = ""
        var streamedMessageID: UUID?
        do {
            for try await token in responder.stream(to: prompt, conversation: conversation) {
                guard activeResponseID == responseID else { return }
                try Task.checkCancellation()
                streamedText.append(token)
                if let streamedMessageID, let index = messages.firstIndex(where: { $0.id == streamedMessageID }) {
                    let message = messages[index]
                    messages[index] = ChatMessage(id: message.id, role: .assistant, text: streamedText, createdAt: message.createdAt)
                } else {
                    let message = ChatMessage(role: .assistant, text: streamedText)
                    streamedMessageID = message.id
                    activeAssistantMessageID = message.id
                    messages.append(message)
                }
                armResponseWatchdog(for: responseID)
                synchronizeCurrentSession(persisting: false)
            }
        } catch is CancellationError {
            // Preserve already-streamed text; cancellation is an expected local action.
        } catch let error as OllamaClientError where error == .cancelled {
            // Preserve already-streamed text; cancellation is an expected local action.
        } catch {
            if activeResponseID == responseID, streamedText.isEmpty {
                messages.append(
                    ChatMessage(
                        role: .assistant,
                        text: "I couldn't complete that local response. Check Ollama in Settings, then try again."
                    )
                )
            }
        }
    }

    func startSendingDraft() {
        guard sendingTask == nil else { return }
        let taskID = UUID()
        sendingTaskID = taskID
        sendingTask = Task { [weak self] in
            guard let self else { return }
            await self.sendDraft()
            guard self.sendingTaskID == taskID else { return }
            self.sendingTask = nil
            self.sendingTaskID = nil
        }
    }

    func cancelSending() {
        sendingTask?.cancel()
        sendingTask = nil
        sendingTaskID = nil
        activeResponseID = nil
        activeAssistantMessageID = nil
        responseWatchdogTask?.cancel()
        responseWatchdogTask = nil
        watchdogResponseID = nil
        isSending = false
        synchronizeCurrentSession()
    }

    func clear() {
        cancelSending()
        messages.removeAll()
        draft = ""
        synchronizeCurrentSession()
    }

    func retryLastResponse() {
        guard !isSending, let userIndex = messages.lastIndex(where: { $0.role == .user }) else { return }
        messages.removeSubrange((userIndex + 1)..<messages.count)
        draft = messages[userIndex].text
        synchronizeCurrentSession()
        startSendingDraft()
    }

    func startNewChat() {
        synchronizeCurrentSession()
        let newSession = ChatSession(messages: [], greeting: greetingProvider())
        openSessions.append(newSession)
        activate(newSession)
    }

    func select(_ session: ChatSession) {
        guard session.id != activeSessionID else { return }
        synchronizeCurrentSession()
        activate(session)
    }

    func close(_ session: ChatSession) {
        guard let index = openSessions.firstIndex(where: { $0.id == session.id }) else { return }

        synchronizeCurrentSession()
        let closingSession = openSessions[index]
        openSessions.remove(at: index)
        pinnedSessionIDs.remove(closingSession.id)
        archivedSessions.removeAll { $0.id == closingSession.id }
        archivedSessions.insert(closingSession, at: 0)

        guard closingSession.id == activeSessionID else {
            persistSessions()
            return
        }

        if let nextSession = openSessions[safe: min(index, openSessions.count - 1)] {
            activate(nextSession)
        } else {
            let replacementSession = ChatSession(messages: [], greeting: greetingProvider())
            openSessions = [replacementSession]
            activate(replacementSession)
        }
        persistSessions()
    }

    func delete(_ session: ChatSession) {
        let deletingActiveSession = session.id == activeSessionID
        if deletingActiveSession {
            cancelSending()
            synchronizeCurrentSession()
        }

        guard let index = openSessions.firstIndex(where: { $0.id == session.id }) else {
            archivedSessions.removeAll { $0.id == session.id }
            pinnedSessionIDs.remove(session.id)
            persistSessions()
            return
        }

        openSessions.remove(at: index)
        archivedSessions.removeAll { $0.id == session.id }
        pinnedSessionIDs.remove(session.id)

        if deletingActiveSession {
            if let nextSession = openSessions[safe: min(index, openSessions.count - 1)] {
                activate(nextSession)
            } else {
                let replacementSession = ChatSession(messages: [], greeting: greetingProvider())
                openSessions = [replacementSession]
                activate(replacementSession)
            }
        }
        persistSessions()
    }

    func restore(_ session: ChatSession) {
        archivedSessions.removeAll { $0.id == session.id }
        if let openSession = openSessions.first(where: { $0.id == session.id }) {
            select(openSession)
        } else {
            synchronizeCurrentSession()
            openSessions.append(session)
            activate(session)
        }
    }

    func clearHistory() {
        archivedSessions.removeAll()
        persistSessions()
    }

    var sidebarSessions: [ChatSession] {
        openSessions.enumerated().sorted { lhs, rhs in
            let lhsIsPinned = pinnedSessionIDs.contains(lhs.element.id)
            let rhsIsPinned = pinnedSessionIDs.contains(rhs.element.id)
            if lhsIsPinned != rhsIsPinned {
                return lhsIsPinned
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    func isPinned(_ session: ChatSession) -> Bool {
        pinnedSessionIDs.contains(session.id)
    }

    func togglePinned(_ session: ChatSession) {
        guard openSessions.contains(where: { $0.id == session.id }) else { return }
        if pinnedSessionIDs.contains(session.id) {
            pinnedSessionIDs.remove(session.id)
        } else {
            pinnedSessionIDs.insert(session.id)
        }
        persistSessions()
    }

    func renameCurrentChat(to proposedTitle: String) {
        guard let session = openSessions.first(where: { $0.id == activeSessionID }) else { return }
        rename(session, to: proposedTitle)
    }

    func rename(_ session: ChatSession, to proposedTitle: String) {
        guard let index = openSessions.firstIndex(where: { $0.id == session.id }) else { return }

        let trimmedTitle = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedTitle.isEmpty ? "Untitled" : String(trimmedTitle.prefix(64))
        let updatedSession = ChatSession(
            id: session.id,
            title: title,
            messages: session.messages,
            greeting: session.greeting,
            updatedAt: .now
        )
        openSessions[index] = updatedSession

        if activeSessionID == session.id {
            currentTitle = title
        }
        persistSessions()
    }

    func restorePersistedSessions() async {
        guard let sessionRepository else { return }
        do {
            let restored = try await sessionRepository.load()
            guard !restored.open.isEmpty || !restored.archived.isEmpty else { return }

            openSessions = restored.open.isEmpty
                ? [ChatSession(messages: [], greeting: greetingProvider())]
                : restored.open
            archivedSessions = restored.archived
            pinnedSessionIDs = restored.pinnedSessionIDs
            activate(openSessions[0])
        } catch {
            // Local chat persistence should never prevent the app opening.
        }
    }

    private func activate(_ session: ChatSession) {
        activeSessionID = session.id
        currentTitle = session.title
        welcomeGreeting = session.greeting
        messages = session.messages
        draft = ""
        isSending = false
    }

    private func synchronizeCurrentSession(persisting: Bool = true) {
        guard let index = openSessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        openSessions[index] = ChatSession(
            id: activeSessionID,
            title: currentTitle,
            messages: messages,
            greeting: welcomeGreeting
        )
        persistSessions(debounced: !persisting)
    }

    private func armResponseWatchdog(for responseID: UUID) {
        responseWatchdogTask?.cancel()
        watchdogResponseID = responseID
        let timeout = responseTimeout
        responseWatchdogTask = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.timeoutResponse(responseID)
        }
    }

    private func timeoutResponse(_ responseID: UUID) {
        guard activeResponseID == responseID else { return }

        let timeoutMessage = "I couldn't complete that local response because the local model didn't respond in time. Check Ollama in Settings, then try again."
        if let messageID = activeAssistantMessageID,
           let index = messages.firstIndex(where: { $0.id == messageID }) {
            let message = messages[index]
            messages[index] = ChatMessage(
                id: message.id,
                role: .assistant,
                text: message.text + "\n\n" + timeoutMessage,
                createdAt: message.createdAt
            )
        } else {
            messages.append(ChatMessage(role: .assistant, text: timeoutMessage))
        }

        activeResponseID = nil
        activeAssistantMessageID = nil
        isSending = false
        sendingTask?.cancel()
        sendingTask = nil
        sendingTaskID = nil
        if watchdogResponseID == responseID {
            responseWatchdogTask?.cancel()
            responseWatchdogTask = nil
            watchdogResponseID = nil
        }
        synchronizeCurrentSession()
    }

    private func finishResponseIfActive(_ responseID: UUID) {
        guard activeResponseID == responseID else { return }
        activeResponseID = nil
        activeAssistantMessageID = nil
        isSending = false
        if watchdogResponseID == responseID {
            responseWatchdogTask?.cancel()
            responseWatchdogTask = nil
            watchdogResponseID = nil
        }
        synchronizeCurrentSession()
    }

    private func persistSessions(debounced: Bool = false) {
        guard let sessionRepository else { return }
        let open = openSessions
        let archived = archivedSessions
        let pinned = pinnedSessionIDs

        if debounced {
            deferredPersistenceTask?.cancel()
            deferredPersistenceTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .milliseconds(350))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.enqueueImmediatePersistence(
                    open: open,
                    archived: archived,
                    pinned: pinned,
                    repository: sessionRepository
                )
            }
            return
        }

        deferredPersistenceTask?.cancel()
        deferredPersistenceTask = nil
        enqueueImmediatePersistence(open: open, archived: archived, pinned: pinned, repository: sessionRepository)
    }

    private func enqueueImmediatePersistence(
        open: [ChatSession],
        archived: [ChatSession],
        pinned: Set<UUID>,
        repository: any ChatSessionPersisting
    ) {
        let previousTask = immediatePersistenceTask
        immediatePersistenceTask = Task {
            await previousTask?.value
            try? await repository.replace(open: open, archived: archived, pinnedSessionIDs: pinned)
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
