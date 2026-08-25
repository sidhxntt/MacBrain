import Foundation

enum OllamaClientError: Error, Sendable, Equatable, LocalizedError {
    case connection(String)
    case server(status: Int, message: String)
    case malformedResponse
    case cancelled

    var errorDescription: String? {
        switch self {
        case .connection:
            return "MacBrain could not reach Ollama at localhost:11434. Start Ollama, then try again."
        case let .server(_, message):
            return message.isEmpty ? "Ollama could not complete this request." : message
        case .malformedResponse:
            return "Ollama returned an unreadable local response."
        case .cancelled:
            return "Local generation was cancelled."
        }
    }
}

struct OllamaClient: Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let retryLimit: Int
    private let retryDelay: Duration

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        session: URLSession = .shared,
        retryLimit: Int = 2,
        retryDelay: Duration = .milliseconds(250)
    ) {
        self.baseURL = baseURL
        self.session = session
        self.retryLimit = max(0, retryLimit)
        self.retryDelay = retryDelay
    }

    func health() async throws {
        _ = try await request(path: "/api/version", method: "GET")
    }

    func models() async throws -> [InferenceModel] {
        let data = try await request(path: "/api/tags", method: "GET")
        let response = try decode(OllamaTagsResponse.self, from: data)
        return response.models.map {
            InferenceModel(
                name: $0.name,
                size: $0.size,
                parameterSize: $0.details?.parameterSize,
                quantization: $0.details?.quantizationLevel
            )
        }
    }

    func embeddings(model: String, input: [String]) async throws -> [[Float]] {
        let data = try await request(
            path: "/api/embed",
            method: "POST",
            body: OllamaEmbeddingRequest(model: model, input: input)
        )
        return try decode(OllamaEmbeddingResponse.self, from: data).embeddings
    }

    func streamChat(model: String, messages: [InferenceChatMessage]) -> AsyncThrowingStream<String, Error> {
        stream(path: "/api/chat", body: OllamaChatRequest(model: model, messages: messages, stream: true)) { data in
            try decode(OllamaChatEvent.self, from: data).message?.content ?? ""
        }
    }

    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> {
        stream(path: "/api/pull", body: OllamaPullRequest(name: model, stream: true)) { data in
            let event = try decode(OllamaPullEvent.self, from: data)
            return OllamaPullProgress(status: event.status, completed: event.completed, total: event.total)
        }
    }

    private func stream<Element: Sendable, Body: Encodable & Sendable>(
        path: String,
        body: Body,
        transform: @escaping @Sendable (Data) throws -> Element
    ) -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await streamRequest(path: path, body: body, transform: transform, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: OllamaClientError.cancelled)
                } catch let error as OllamaClientError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: OllamaClientError.connection(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func streamRequest<Element: Sendable, Body: Encodable & Sendable>(
        path: String,
        body: Body,
        transform: @escaping @Sendable (Data) throws -> Element,
        continuation: AsyncThrowingStream<Element, Error>.Continuation
    ) async throws {
        let encodedBody = try JSONEncoder().encode(body)
        let request = makeRequest(path: path, method: "POST", body: encodedBody)

        for attempt in 0...retryLimit {
            do {
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw OllamaClientError.malformedResponse
                }

                guard (200..<300).contains(http.statusCode) else {
                    var errorData = Data()
                    for try await byte in bytes {
                        errorData.append(byte)
                    }
                    let message = (try? decode(OllamaErrorResponse.self, from: errorData).error) ?? ""
                    throw OllamaClientError.server(status: http.statusCode, message: message)
                }

                for try await line in bytes.lines where !line.isEmpty {
                    try Task.checkCancellation()
                    continuation.yield(try transform(Data(line.utf8)))
                }
                return
            } catch let error as OllamaClientError {
                if attempt < retryLimit, error.isTransient {
                    try await Task.sleep(for: retryDelay)
                    continue
                }
                throw error
            } catch is CancellationError {
                throw OllamaClientError.cancelled
            } catch {
                if attempt < retryLimit {
                    try await Task.sleep(for: retryDelay)
                    continue
                }
                throw OllamaClientError.connection(error.localizedDescription)
            }
        }

        throw OllamaClientError.connection("Ollama streaming request did not complete.")
    }

    private func request(path: String, method: String) async throws -> Data {
        try await performRequest(path: path, method: method, body: nil)
    }

    private func request<Body: Encodable & Sendable>(path: String, method: String, body: Body) async throws -> Data {
        let encodedBody = try JSONEncoder().encode(body)
        return try await performRequest(path: path, method: method, body: encodedBody)
    }

    private func performRequest(path: String, method: String, body: Data?) async throws -> Data {
        let request = makeRequest(path: path, method: method, body: body)

        for attempt in 0...retryLimit {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw OllamaClientError.malformedResponse }
                guard (200..<300).contains(http.statusCode) else {
                    let message = (try? decode(OllamaErrorResponse.self, from: data).error) ?? ""
                    throw OllamaClientError.server(status: http.statusCode, message: message)
                }
                return data
            } catch let error as OllamaClientError {
                if attempt < retryLimit, error.isTransient {
                    try await Task.sleep(for: retryDelay)
                    continue
                }
                throw error
            } catch is CancellationError {
                throw OllamaClientError.cancelled
            } catch {
                if attempt < retryLimit {
                    try await Task.sleep(for: retryDelay)
                    continue
                }
                throw OllamaClientError.connection(error.localizedDescription)
            }
        }
        throw OllamaClientError.connection("Ollama request did not complete.")
    }

    private func makeRequest(path: String, method: String, body: Data?) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw OllamaClientError.malformedResponse
        }
    }
}

private extension OllamaClientError {
    var isTransient: Bool {
        switch self {
        case .connection: true
        case let .server(status, _): status >= 500
        case .malformedResponse, .cancelled: false
        }
    }
}

private struct OllamaTagsResponse: Decodable {
    let models: [OllamaModel]
}

private struct OllamaModel: Decodable {
    let name: String
    let size: Int64?
    let details: OllamaModelDetails?
}

private struct OllamaModelDetails: Decodable {
    let parameterSize: String?
    let quantizationLevel: String?

    enum CodingKeys: String, CodingKey {
        case parameterSize = "parameter_size"
        case quantizationLevel = "quantization_level"
    }
}

private struct OllamaEmbeddingRequest: Encodable {
    let model: String
    let input: [String]
}

private struct OllamaEmbeddingResponse: Decodable {
    let embeddings: [[Float]]
}

private struct OllamaChatRequest: Encodable {
    let model: String
    let messages: [InferenceChatMessage]
    let stream: Bool
}

private struct OllamaChatEvent: Decodable {
    let message: InferenceChatMessage?
}

private struct OllamaPullRequest: Encodable {
    let name: String
    let stream: Bool
}

private struct OllamaPullEvent: Decodable {
    let status: String
    let completed: Int64?
    let total: Int64?
}

private struct OllamaErrorResponse: Decodable {
    let error: String
}
