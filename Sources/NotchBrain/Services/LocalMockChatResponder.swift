import Foundation

struct LocalMockChatResponder: ChatResponder {
    func respond(to prompt: String) async throws -> String {
        try await Task.sleep(nanoseconds: 350_000_000)
        return "I found your note: \"\(prompt)\"\n\nThis local response is ready for MacBrain's on-device memory and retrieval layer."
    }
}
