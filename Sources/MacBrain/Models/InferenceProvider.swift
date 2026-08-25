import Foundation

enum InferenceRole: String, Codable, Sendable, Equatable {
    case system
    case user
    case assistant
}

struct InferenceChatMessage: Codable, Sendable, Equatable {
    let role: InferenceRole
    let content: String

    static func system(_ content: String) -> Self { .init(role: .system, content: content) }
    static func user(_ content: String) -> Self { .init(role: .user, content: content) }
    static func assistant(_ content: String) -> Self { .init(role: .assistant, content: content) }
}

struct InferenceModel: Codable, Sendable, Equatable, Identifiable {
    let name: String
    let size: Int64?
    let parameterSize: String?
    let quantization: String?

    var id: String { name }
}

struct InferenceEmbedding: Sendable, Equatable {
    let values: [Float]
}

struct OllamaPullProgress: Sendable, Equatable {
    let status: String
    let completed: Int64?
    let total: Int64?

    var fractionCompleted: Double? {
        guard let completed, let total, total > 0 else { return nil }
        return min(1, Double(completed) / Double(total))
    }
}

enum InferenceProviderStatus: Sendable, Equatable {
    case checking
    case runtimeMissing
    case unavailable(String)
    case ready(models: [InferenceModel])
}

protocol InferenceProvider: Sendable {
    func status() async -> InferenceProviderStatus
    func streamChat(model: String, messages: [InferenceChatMessage]) -> AsyncThrowingStream<String, Error>
    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding]
    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error>
    func unload(model: String) async
}

extension InferenceProvider {
    /// Providers that cannot explicitly unload retain their existing lifecycle behavior.
    func unload(model: String) async {}
}
