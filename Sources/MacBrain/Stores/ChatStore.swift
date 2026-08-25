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
    private let sessionRepository: LocalChatSessionRepository?
    private var sendingTask: Task<Void, Never>?

    init(
        responder: any ChatResponder = LocalMockChatResponder(),
        greetingProvider: @escaping () -> String = { MacBrainGreeting.random() },
        sessionRepository: LocalChatSessionRepository? = nil
    ) {
        let initialGreeting = greetingProvider()
        let initialSession = ChatSession(messages: [], greeting: initialGreeting)
        self.responder = responder
        self.greetingProvider = greetingProvider
        self.sessionRepository = sessionRepository
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
        messages.append(ChatMessage(role: .user, text: prompt))
        synchronizeCurrentSession()
        isSending = true
        defer { isSending = false }

        var streamedText = ""
        var streamedMessageID: UUID?
        do {
            for try await token in responder.stream(to: prompt) {
                try Task.checkCancellation()
                streamedText.append(token)
                if let streamedMessageID, let index = messages.firstIndex(where: { $0.id == streamedMessageID }) {
                    let message = messages[index]
                    messages[index] = ChatMessage(id: message.id, role: .assistant, text: streamedText, createdAt: message.createdAt)
                } else {
                    let message = ChatMessage(role: .assistant, text: streamedText)
                    streamedMessageID = message.id
                    messages.append(message)
                }
                synchronizeCurrentSession()
            }
        } catch is CancellationError {
            // Preserve already-streamed text; cancellation is an expected local action.
        } catch let error as OllamaClientError where error == .cancelled {
            // Preserve already-streamed text; cancellation is an expected local action.
        } catch {
            if streamedText.isEmpty {
                messages.append(
                    ChatMessage(
                        role: .assistant,
                        text: "I couldn't complete that local response. Check Ollama in Settings, then try again."
                    )
                )
            }
            synchronizeCurrentSession()
        }
    }

    func startSendingDraft() {
        guard sendingTask == nil else { return }
        sendingTask = Task { [weak self] in
            guard let self else { return }
            await self.sendDraft()
            self.sendingTask = nil
        }
    }

    func cancelSending() {
        sendingTask?.cancel()
        sendingTask = nil
        isSending = false
        synchronizeCurrentSession()
    }

    func clear() {
        messages.removeAll()
        draft = ""
        isSending = false
        synchronizeCurrentSession()
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

        guard closingSession.id == activeSessionID else { return }

        if let nextSession = openSessions[safe: min(index, openSessions.count - 1)] {
            activate(nextSession)
        } else {
            let replacementSession = ChatSession(messages: [], greeting: greetingProvider())
            openSessions = [replacementSession]
            activate(replacementSession)
        }
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

    private func synchronizeCurrentSession() {
        guard let index = openSessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        openSessions[index] = ChatSession(
            id: activeSessionID,
            title: currentTitle,
            messages: messages,
            greeting: welcomeGreeting
        )
        persistSessions()
    }

    private func persistSessions() {
        guard let sessionRepository else { return }
        let open = openSessions
        let archived = archivedSessions
        let pinned = pinnedSessionIDs
        Task {
            try? await sessionRepository.replace(open: open, archived: archived, pinnedSessionIDs: pinned)
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
