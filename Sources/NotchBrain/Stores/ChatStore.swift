import Combine
import Foundation

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var openSessions: [ChatSession]
    @Published private(set) var archivedSessions: [ChatSession] = []
    @Published private(set) var activeSessionID: UUID
    @Published private(set) var currentTitle = "Untitled"
    @Published private(set) var welcomeGreeting: String
    @Published var draft = ""
    @Published private(set) var isSending = false

    private let responder: any ChatResponder
    private let greetingProvider: () -> String

    init(
        responder: any ChatResponder = LocalMockChatResponder(),
        greetingProvider: @escaping () -> String = { MacBrainGreeting.random() }
    ) {
        let initialGreeting = greetingProvider()
        let initialSession = ChatSession(messages: [], greeting: initialGreeting)
        self.responder = responder
        self.greetingProvider = greetingProvider
        self.openSessions = [initialSession]
        self.activeSessionID = initialSession.id
        self.welcomeGreeting = initialGreeting
    }

    func sendDraft() async {
        guard !isSending else { return }

        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        draft = ""
        messages.append(ChatMessage(role: .user, text: prompt))
        synchronizeCurrentSession()
        isSending = true
        defer { isSending = false }

        do {
            let response = try await responder.respond(to: prompt)
            messages.append(ChatMessage(role: .assistant, text: response))
            synchronizeCurrentSession()
        } catch {
            messages.append(
                ChatMessage(
                    role: .assistant,
                    text: "I couldn't complete that local response. Please try again."
                )
            )
            synchronizeCurrentSession()
        }
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
    }

    func renameCurrentChat(to proposedTitle: String) {
        let title = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        currentTitle = title.isEmpty ? "Untitled" : String(title.prefix(64))
        synchronizeCurrentSession()
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
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
