import Foundation

struct ChatSession: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let messages: [ChatMessage]
    let greeting: String
    let modelIdentifier: String
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "Untitled",
        messages: [ChatMessage],
        greeting: String = MacBrainGreeting.random(),
        modelIdentifier: String = "local",
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.greeting = greeting
        self.modelIdentifier = modelIdentifier
        self.updatedAt = updatedAt
    }
}
