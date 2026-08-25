import Foundation

struct PersistedChatSessions: Sendable {
    let open: [ChatSession]
    let archived: [ChatSession]
    let pinnedSessionIDs: Set<UUID>
}

protocol ChatSessionPersisting: Sendable {
    func load() async throws -> PersistedChatSessions
    func replace(open: [ChatSession], archived: [ChatSession], pinnedSessionIDs: Set<UUID>) async throws
}

actor LocalChatSessionRepository: ChatSessionPersisting {
    private let database: MacBrainDatabase

    init(database: MacBrainDatabase) {
        self.database = database
    }

    func load() async throws -> PersistedChatSessions {
        let conversations = try await database.conversations()
        var open: [ChatSession] = []
        var archived: [ChatSession] = []
        var pinnedSessionIDs = Set<UUID>()

        for conversation in conversations {
            let messages = try await database.messages(conversationID: conversation.id).map(ChatMessage.init)
            let session = ChatSession(
                id: conversation.id,
                title: conversation.title,
                messages: messages,
                greeting: conversation.greeting,
                modelIdentifier: conversation.modelIdentifier,
                updatedAt: conversation.updatedAt
            )
            if conversation.isArchived {
                archived.append(session)
            } else {
                open.append(session)
            }
            if conversation.isPinned { pinnedSessionIDs.insert(conversation.id) }
        }
        return PersistedChatSessions(open: open, archived: archived, pinnedSessionIDs: pinnedSessionIDs)
    }

    func replace(open: [ChatSession], archived: [ChatSession], pinnedSessionIDs: Set<UUID>) async throws {
        let entries = (open.map { ($0, false) } + archived.map { ($0, true) }).map { session, isArchived in
            (
                conversation: StoredConversation(
                    id: session.id,
                    title: session.title,
                    greeting: session.greeting,
                    modelIdentifier: session.modelIdentifier,
                    updatedAt: session.updatedAt,
                    isArchived: isArchived,
                    isPinned: pinnedSessionIDs.contains(session.id)
                ),
                messages: session.messages.map { StoredMessage($0, conversationID: session.id) }
            )
        }
        try await database.replaceConversations(entries)
    }
}

private extension ChatMessage {
    init(_ message: StoredMessage) {
        self.init(
            id: message.id,
            role: message.role == .user ? .user : .assistant,
            text: message.text,
            createdAt: message.createdAt
        )
    }
}

private extension StoredMessage {
    init(_ message: ChatMessage, conversationID: UUID) {
        self.init(
            id: message.id,
            conversationID: conversationID,
            role: message.role == .user ? .user : .assistant,
            text: message.text,
            createdAt: message.createdAt
        )
    }
}
