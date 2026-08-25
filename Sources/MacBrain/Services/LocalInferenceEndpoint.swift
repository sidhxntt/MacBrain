import Foundation

/// MacBrain's inference transport is intentionally restricted to loopback so
/// prompts, evidence, and embeddings cannot be redirected to a hosted API.
enum LocalInferenceEndpoint {
    static let defaultURL = URL(string: "http://127.0.0.1:11434")!

    static func isApproved(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http",
              let host = url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    static func resolvedURL(for candidate: URL) -> URL {
        isApproved(candidate) ? candidate : defaultURL
    }
}
