import Foundation

struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Equatable, Sendable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let text: String
    let createdAt: Date
    let groundingSourceIDs: [String]

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        createdAt: Date = .now,
        groundingSourceIDs: [String] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.groundingSourceIDs = groundingSourceIDs
    }
}
