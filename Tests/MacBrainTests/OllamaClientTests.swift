import Foundation
import XCTest
@testable import MacBrain

final class OllamaClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockOllamaURLProtocol.handler = nil
    }

    func testModelsDecodesLocalTagsResponse() async throws {
        let client = OllamaClient(baseURL: URL(string: "http://127.0.0.1:11434")!, session: mockSession())
        MockOllamaURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/tags")
            return Self.response(
                body: #"{"models":[{"name":"qwen3:8b","size":5200000000,"details":{"parameter_size":"8B","quantization_level":"Q4_K_M"}}]}"#
            )
        }

        let models = try await client.models()

        XCTAssertEqual(models.map(\.name), ["qwen3:8b"])
        XCTAssertEqual(models.first?.parameterSize, "8B")
        XCTAssertEqual(models.first?.quantization, "Q4_K_M")
    }

    func testModelsNormalizesOllamaLatestTagToRequestedModelName() async throws {
        let client = OllamaClient(baseURL: URL(string: "http://127.0.0.1:11434")!, session: mockSession())
        MockOllamaURLProtocol.handler = { _ in
            Self.response(body: #"{"models":[{"name":"nomic-embed-text:latest"}]}"#)
        }

        let models = try await client.models()

        XCTAssertEqual(models.map(\.name), ["nomic-embed-text"])
    }

    func testStreamingChatEmitsEachTokenInOrder() async throws {
        let client = OllamaClient(baseURL: URL(string: "http://127.0.0.1:11434")!, session: mockSession())
        MockOllamaURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/chat")
            return Self.response(body: """
            {"message":{"role":"assistant","content":"Hello"},"done":false}
            {"message":{"role":"assistant","content":" world"},"done":true}
            """)
        }

        var tokens: [String] = []
        for try await token in client.streamChat(model: "qwen3:8b", messages: [.user("Hi")]) {
            tokens.append(token)
        }

        XCTAssertEqual(tokens, ["Hello", " world"])
    }

    func testStreamingChatDisablesReasoningForResponsiveVisibleTokens() async throws {
        let request = OllamaChatRequest(
            model: "qwen3:8b",
            messages: [.user("Hi")],
            stream: true,
            think: false
        )

        let payload = try JSONEncoder().encode(request)

        XCTAssertTrue(try XCTUnwrap(String(data: payload, encoding: .utf8)).contains("\"think\":false"))
    }

    func testStreamingChatRequestKeepsLocalModelWarmWithDeterministicOptions() throws {
        let request = OllamaChatRequest(
            model: "qwen3:8b",
            messages: [.user("Hi")],
            stream: true,
            think: false
        )

        let payload = try XCTUnwrap(String(data: JSONEncoder().encode(request), encoding: .utf8))

        XCTAssertTrue(payload.contains("\"keep_alive\":\"30m\""))
        XCTAssertTrue(payload.contains("\"temperature\":0.2"))
    }

    func testServerFailureExposesActionableError() async {
        let client = OllamaClient(baseURL: URL(string: "http://127.0.0.1:11434")!, session: mockSession())
        MockOllamaURLProtocol.handler = { _ in Self.response(status: 500, body: #"{"error":"model missing"}"#) }

        do {
            _ = try await client.models()
            XCTFail("Expected Ollama server failure")
        } catch let error as OllamaClientError {
            XCTAssertEqual(error, .server(status: 500, message: "model missing"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEmbeddingsDecodesVectors() async throws {
        let client = OllamaClient(baseURL: URL(string: "http://127.0.0.1:11434")!, session: mockSession())
        MockOllamaURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/embed")
            return Self.response(body: #"{"embeddings":[[0.25,0.5,-0.25]]}"#)
        }

        let vectors = try await client.embeddings(model: "nomic-embed-text", input: ["MacBrain"])

        XCTAssertEqual(vectors, [[0.25, 0.5, -0.25]])
    }

    func testRetriesTransientLocalConnection() async throws {
        let client = OllamaClient(baseURL: URL(string: "http://127.0.0.1:11434")!, session: mockSession(), retryLimit: 1)
        var attempts = 0
        MockOllamaURLProtocol.handler = { _ in
            attempts += 1
            if attempts == 1 { throw URLError(.cannotConnectToHost) }
            return Self.response(body: #"{"models":[]}"#)
        }

        let models = try await client.models()

        XCTAssertTrue(models.isEmpty)
        XCTAssertEqual(attempts, 2)
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockOllamaURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(status: Int = 200, body: String) -> MockOllamaURLProtocol.Response {
        .init(status: status, body: Data(body.utf8))
    }
}

private final class MockOllamaURLProtocol: URLProtocol {
    struct Response {
        let status: Int
        let body: Data
    }

    nonisolated(unsafe) static var handler: ((URLRequest) throws -> Response)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let response: Response
        do {
            response = try handler(request)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let urlResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: urlResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
