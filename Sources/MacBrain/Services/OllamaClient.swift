import Foundation

enum OllamaClientError: Error, Sendable, Equatable, LocalizedError {
    case connection(String)
    case server(status: Int, message: String)
    case malformedResponse
    case cancelled
    case timedOut

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
        case .timedOut:
            return "MacBrain did not receive a local response in time. Try again or choose a smaller model in Settings."
        }
    }
}

struct OllamaClient: Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let retryLimit: Int
    private let retryDelay: Duration
    private let firstTokenTimeout: Duration

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        session: URLSession = .shared,
        retryLimit: Int = 2,
        retryDelay: Duration = .milliseconds(250),
        firstTokenTimeout: Duration = .seconds(15)
    ) {
        self.baseURL = baseURL
        self.session = session
        self.retryLimit = max(0, retryLimit)
        self.retryDelay = retryDelay
        self.firstTokenTimeout = firstTokenTimeout
    }

    func health() async throws {
        _ = try await request(path: "/api/version", method: "GET")
    }

    func models() async throws -> [InferenceModel] {
        let data = try await request(path: "/api/tags", method: "GET")
        let response = try decode(OllamaTagsResponse.self, from: data)
        return response.models.map {
            InferenceModel(
                name: canonicalModelName($0.name),
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
        stream(
            path: "/api/chat",
            body: OllamaChatRequest(model: model, messages: messages, stream: true, think: false),
            firstTokenTimeout: firstTokenTimeout
        ) { data in
            try decode(OllamaChatEvent.self, from: data).message?.content ?? ""
        }
    }

    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> {
        stream(path: "/api/pull", body: OllamaPullRequest(name: model, stream: true), firstTokenTimeout: nil) { data in
            let event = try decode(OllamaPullEvent.self, from: data)
            return OllamaPullProgress(status: event.status, completed: event.completed, total: event.total)
        }
    }

    func unload(model: String) async throws {
        _ = try await request(path: "/api/chat", method: "POST", body: OllamaUnloadRequest(model: model))
    }

    private func stream<Element: Sendable, Body: Encodable & Sendable>(
        path: String,
        body: Body,
        firstTokenTimeout: Duration?,
        transform: @escaping @Sendable (Data) throws -> Element
    ) -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let watchdog = FirstTokenWatchdog()
                let timeoutTask = firstTokenTimeout.map { timeout in
                    Task {
                        do {
                            try await Task.sleep(for: timeout)
                            guard !Task.isCancelled, await !watchdog.didReceiveToken() else { return }
                            await watchdog.markTimedOut()
                            continuation.finish(throwing: OllamaClientError.timedOut)
                        } catch {
                            // Cancellation means a local token arrived or the stream ended.
                        }
                    }
                }
                defer { timeoutTask?.cancel() }
                do {
                    try await streamRequest(
                        path: path,
                        body: body,
                        transform: transform,
                        continuation: continuation,
                        onFirstElement: { await watchdog.markReceivedToken() }
                    )
                    guard !(await watchdog.didTimeOut()) else { return }
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
        continuation: AsyncThrowingStream<Element, Error>.Continuation,
        onFirstElement: @escaping @Sendable () async -> Void
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
                    let element = try transform(Data(line.utf8))
                    await onFirstElement()
                    continuation.yield(element)
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

    private func canonicalModelName(_ name: String) -> String {
        name.hasSuffix(":latest") ? String(name.dropLast(7)) : name
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw OllamaClientError.malformedResponse
        }
    }
}

private actor FirstTokenWatchdog {
    private var receivedToken = false
    private var timedOut = false

    func markReceivedToken() {
        receivedToken = true
    }

    func markTimedOut() {
        timedOut = true
    }

    func didReceiveToken() -> Bool { receivedToken }
    func didTimeOut() -> Bool { timedOut }
}

private extension OllamaClientError {
    var isTransient: Bool {
        switch self {
        case .connection: true
        case let .server(status, _): status >= 500
        case .malformedResponse, .cancelled, .timedOut: false
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

struct OllamaChatRequest: Encodable {
    let model: String
    let messages: [InferenceChatMessage]
    let stream: Bool
    let think: Bool
    let keepAlive: String
    let options: OllamaChatOptions

    init(
        model: String,
        messages: [InferenceChatMessage],
        stream: Bool,
        think: Bool,
        keepAlive: String = "30m",
        options: OllamaChatOptions = .macBrainDefaults
    ) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.think = think
        self.keepAlive = keepAlive
        self.options = options
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, think, options
        case keepAlive = "keep_alive"
    }
}

struct OllamaChatOptions: Encodable {
    let temperature: Double
    let numContext: Int
    let numPredict: Int

    static let macBrainDefaults = Self(temperature: 0.2, numContext: 8_192, numPredict: 256)

    enum CodingKeys: String, CodingKey {
        case temperature
        case numContext = "num_ctx"
        case numPredict = "num_predict"
    }
}

private struct OllamaChatEvent: Decodable {
    let message: InferenceChatMessage?
}

private struct OllamaPullRequest: Encodable {
    let name: String
    let stream: Bool
}

private struct OllamaUnloadRequest: Encodable {
    let model: String
    let messages: [InferenceChatMessage] = []
    let keepAlive = "0"
    let stream = false

    enum CodingKeys: String, CodingKey {
        case model, messages, stream
        case keepAlive = "keep_alive"
    }
}

private struct OllamaPullEvent: Decodable {
    let status: String
    let completed: Int64?
    let total: Int64?
}

private struct OllamaErrorResponse: Decodable {
    let error: String
}
