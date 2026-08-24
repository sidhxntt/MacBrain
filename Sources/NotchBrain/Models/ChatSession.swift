import Foundation

struct ChatSession: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let messages: [ChatMessage]
    let greeting: String
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "Untitled",
        messages: [ChatMessage],
        greeting: String = MacBrainGreeting.random(),
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.greeting = greeting
        self.updatedAt = updatedAt
    }
}
