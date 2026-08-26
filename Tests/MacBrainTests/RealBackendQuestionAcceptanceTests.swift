import Foundation
import XCTest
@testable import MacBrain

final class RealBackendQuestionAcceptanceTests: XCTestCase {
    func testManualQuestionsReachTheProductionBackend() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MACBRAIN_REAL_BACKEND_QUESTIONS"] == "1",
            "Set MACBRAIN_REAL_BACKEND_QUESTIONS=1 to run the user-approved local-data acceptance check."
        )

        let questionFile = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("question-to-ask.md")
        let questions = try String(contentsOf: questionFile, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let question = line.trimmingCharacters(in: .whitespaces)
                guard question.hasPrefix("- ") else { return nil }
                return String(question.dropFirst(2))
            }
        let limit = Int(ProcessInfo.processInfo.environment["MACBRAIN_REAL_BACKEND_QUESTION_LIMIT"] ?? "0") ?? 0
        let selectedQuestions = limit > 0 ? Array(questions.prefix(limit)) : questions
        XCTAssertFalse(selectedQuestions.isEmpty)

        let database = try MacBrainDatabase()
        let repository = LocalSourceRepository(database: database)
        try await repository.bootstrap()
        let responder = StreamingChatResponder(
            provider: OllamaProvider(client: OllamaClient(retryLimit: 0, firstTokenTimeout: .seconds(30))),
            repository: repository,
            selectedModel: { ProcessInfo.processInfo.environment["MACBRAIN_LIVE_CHAT_MODEL"] ?? "qwen3:8b" },
            selectedEmbeddingModel: { ProcessInfo.processInfo.environment["MACBRAIN_LIVE_EMBEDDING_MODEL"] ?? "nomic-embed-text" },
            fallback: LocalMockChatResponder(),
            providerStatusTimeout: .seconds(8),
            retrievalTimeout: .seconds(10)
        )

        for (index, question) in selectedQuestions.enumerated() {
            let terminal = await Self.response(
                from: responder,
                to: question,
                timeout: .seconds(45)
            )
            guard case let .completed(response) = terminal else {
                return XCTFail("Question \(index + 1) did not complete: \(terminal).")
            }
            XCTAssertFalse(
                response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Question \(index + 1) produced no response."
            )
            XCTAssertFalse(
                response.contains("local model didn't respond in time"),
                "Question \(index + 1) reached the UI timeout path."
            )
        }
    }

    private static func response(
        from responder: StreamingChatResponder,
        to question: String,
        timeout: Duration
    ) async -> BackendQuestionTerminal {
        let race = BackendQuestionRace()
        let task = Task {
            do {
                await race.resolve(.completed(try await responder.respond(to: question)))
            } catch {
                await race.resolve(.failed)
            }
        }
        let watchdog = Task {
            do {
                try await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                task.cancel()
                await race.resolve(.timedOut)
            } catch {
                return
            }
        }
        let result = await race.wait()
        watchdog.cancel()
        return result
    }
}

private enum BackendQuestionTerminal: CustomStringConvertible {
    case completed(String)
    case failed
    case timedOut

    var description: String {
        switch self {
        case .completed: "completed"
        case .failed: "failed"
        case .timedOut: "timedOut"
        }
    }
}

private actor BackendQuestionRace {
    private var result: BackendQuestionTerminal?
    private var continuation: CheckedContinuation<BackendQuestionTerminal, Never>?

    func wait() async -> BackendQuestionTerminal {
        if let result { return result }
        return await withCheckedContinuation { continuation in
            if let result { continuation.resume(returning: result) }
            else { self.continuation = continuation }
        }
    }

    func resolve(_ result: BackendQuestionTerminal) {
        guard self.result == nil else { return }
        self.result = result
        continuation?.resume(returning: result)
        continuation = nil
    }
}
