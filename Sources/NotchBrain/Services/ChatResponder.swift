protocol ChatResponder: Sendable {
    func respond(to prompt: String) async throws -> String
}
