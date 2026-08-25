import XCTest
@testable import MacBrain

@MainActor
final class ChatStoreTests: XCTestCase {
    func testWhitespaceDraftDoesNotSend() async {
        let responder = RecordingResponder()
        let store = ChatStore(responder: responder)
        store.draft = "   \n"

        await store.sendDraft()

        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertFalse(store.isSending)
        XCTAssertNil(responder.lastPrompt)
    }

    func testSendAppendsUserThenAssistantResponse() async {
        let store = ChatStore(responder: ImmediateResponder(reply: "Local answer"))
        store.draft = "What did I work on?"

        await store.sendDraft()

        XCTAssertEqual(store.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(store.messages[0].text, "What did I work on?")
        XCTAssertEqual(store.messages[1].text, "Local answer")
        XCTAssertFalse(store.isSending)
    }

    func testSendingConsumesOneTurnContextWithoutShowingItAsUserMessage() async {
        let safeguards = ContextSafeguards()
        safeguards.enable(.clipboard, value: "private clipboard")
        let responder = RecordingResponder()
        let store = ChatStore(responder: responder, contextSafeguards: safeguards)
        store.draft = "Summarize this"

        await store.sendDraft()

        XCTAssertEqual(store.messages.first?.text, "Summarize this")
        XCTAssertTrue(responder.lastPrompt?.contains("private clipboard") == true)
        XCTAssertTrue(safeguards.visibleChips.isEmpty)
    }

    func testSecondSendIsIgnoredWhileFirstResponseIsPending() async {
        let started = expectation(description: "First response started")
        let responder = DelayedResponder(onStart: { started.fulfill() })
        let store = ChatStore(responder: responder)
        store.draft = "First"
        let firstSend = Task { await store.sendDraft() }
        await fulfillment(of: [started], timeout: 1)

        store.draft = "Second"
        await store.sendDraft()
        responder.finish()
        await firstSend.value

        XCTAssertEqual(store.messages.map(\.text), ["First", "Reply to First"])
    }

    func testClearResetsConversationAndDraft() async {
        let store = ChatStore(responder: ImmediateResponder(reply: "Reply"))
        store.draft = "Hello"
        await store.sendDraft()
        store.draft = "Unsent"

        store.clear()

        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertEqual(store.draft, "")
        XCTAssertFalse(store.isSending)
    }

    func testNewChatCreatesAnAdditionalOpenSession() async {
        let store = ChatStore(responder: ImmediateResponder(reply: "Reply"))
        store.draft = "Previous conversation"
        await store.sendDraft()

        store.startNewChat()

        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertEqual(store.openSessions.count, 2)
        XCTAssertTrue(store.archivedSessions.isEmpty)
    }

    func testSelectingChatRestoresItsConversation() async {
        let store = ChatStore(responder: ImmediateResponder(reply: "Reply"))
        store.draft = "First chat"
        await store.sendDraft()
        store.renameCurrentChat(to: "First chat")
        store.startNewChat()
        let firstSession = try! XCTUnwrap(store.openSessions.first)
        store.draft = "Second chat"
        await store.sendDraft()
        store.renameCurrentChat(to: "Second chat")

        store.select(firstSession)

        XCTAssertEqual(store.currentTitle, "First chat")
        XCTAssertEqual(store.messages.map(\.text), ["First chat", "Reply"])
    }

    func testRenamePersistsWhenSwitchingSessions() async {
        let store = ChatStore(responder: ImmediateResponder(reply: "Reply"))
        store.renameCurrentChat(to: "Research")
        store.startNewChat()

        XCTAssertEqual(store.currentTitle, "Untitled")
        let research = try! XCTUnwrap(store.openSessions.first)
        store.select(research)

        XCTAssertEqual(store.currentTitle, "Research")
    }

    func testRenamingRecentChatUpdatesThatSessionWithoutChangingActiveChat() {
        let store = ChatStore()
        store.renameCurrentChat(to: "Active")
        store.startNewChat()
        let recentSession = try! XCTUnwrap(store.openSessions.first)

        store.rename(recentSession, to: "Renamed recent")

        XCTAssertEqual(store.openSessions.first?.title, "Renamed recent")
        XCTAssertNotEqual(store.activeSessionID, recentSession.id)
        XCTAssertEqual(store.currentTitle, "Untitled")
    }

    func testNewChatCreatesSessionEvenWhenCurrentChatIsEmpty() {
        let store = ChatStore()

        store.startNewChat()

        XCTAssertEqual(store.openSessions.count, 2)
        XCTAssertTrue(store.archivedSessions.isEmpty)
    }

    func testPinningChatMovesItToBeginningOfSidebarList() {
        let store = ChatStore()
        let first = try! XCTUnwrap(store.openSessions.first)
        store.startNewChat()
        let second = try! XCTUnwrap(store.openSessions.last)

        store.togglePinned(second)

        XCTAssertTrue(store.isPinned(second))
        XCTAssertEqual(store.sidebarSessions.map(\.id), [second.id, first.id])
    }

    func testBlankRenameFallsBackToUntitledAndLongTitleIsLimited() {
        let store = ChatStore()
        store.renameCurrentChat(to: "   ")
        XCTAssertEqual(store.currentTitle, "Untitled")

        store.renameCurrentChat(to: String(repeating: "a", count: 80))
        XCTAssertEqual(store.currentTitle.count, 64)
    }

    func testClosingActiveChatSelectsAdjacentTabAndAddsItToHistory() {
        let store = ChatStore()
        store.renameCurrentChat(to: "First")
        let firstSession = store.openSessions[0]
        store.startNewChat()
        store.renameCurrentChat(to: "Second")
        let secondSession = try! XCTUnwrap(store.openSessions.last)

        store.close(secondSession)

        XCTAssertEqual(store.currentTitle, "First")
        XCTAssertEqual(store.openSessions.map(\.title), ["First"])
        XCTAssertEqual(store.archivedSessions.map(\.title), ["Second"])
        XCTAssertEqual(store.activeSessionID, firstSession.id)
    }

    func testClosingLastTabCreatesReplacementUntitledTab() {
        let store = ChatStore()
        let original = store.openSessions[0]

        store.close(original)

        XCTAssertEqual(store.openSessions.count, 1)
        XCTAssertEqual(store.currentTitle, "Untitled")
        XCTAssertEqual(store.archivedSessions.map(\.title), ["Untitled"])
    }

    func testGreetingCatalogContainsFiftyUniqueGreetings() {
        XCTAssertEqual(MacBrainGreeting.all.count, 50)
        XCTAssertEqual(Set(MacBrainGreeting.all).count, 50)
    }

    func testNewChatUsesANewlySelectedGreeting() {
        let greetings = GreetingSequence(["First greeting", "Second greeting"])
        let store = ChatStore(greetingProvider: greetings.next)

        XCTAssertEqual(store.welcomeGreeting, "First greeting")

        store.startNewChat()

        XCTAssertEqual(store.welcomeGreeting, "Second greeting")
        XCTAssertEqual(store.openSessions.last?.greeting, "Second greeting")
    }

    func testFirstMessageAutomaticallyTitlesUntitledChat() async {
        let store = ChatStore(responder: ImmediateResponder(reply: "Reply"))
        store.draft = "Summarize my product research notes"

        await store.sendDraft()

        XCTAssertEqual(store.currentTitle, "Summarize my product research notes")
        XCTAssertEqual(store.openSessions.first?.title, "Summarize my product research notes")
    }

    func testStreamingResponseShowsPartialTextAndCancellationKeepsIt() async throws {
        let store = ChatStore(responder: SlowStreamingResponder())
        store.draft = "Stream this"

        store.startSendingDraft()
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(store.messages.map(\.text), ["Stream this", "Partial"])
        XCTAssertTrue(store.isSending)

        store.cancelSending()
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(store.messages.map(\.text), ["Stream this", "Partial"])
        XCTAssertFalse(store.isSending)
    }

    func testTimedOutResponseReleasesTheComposerAndExplainsWhatHappened() async throws {
        let store = ChatStore(
            responder: NeverEndingResponder(),
            responseTimeout: .milliseconds(50)
        )
        store.draft = "Who am I?"

        store.startSendingDraft()
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertFalse(store.isSending)
        XCTAssertEqual(
            store.messages.map(\ChatMessage.role),
            [ChatMessage.Role.user, ChatMessage.Role.assistant]
        )
        XCTAssertTrue(store.messages.last?.text.contains("didn't respond in time") == true)
    }

    func testStreamingProgressRenewsTheResponseTimeout() async throws {
        let store = ChatStore(
            responder: ProgressingSlowResponder(),
            responseTimeout: .milliseconds(50)
        )
        store.draft = "Keep streaming"

        store.startSendingDraft()
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertFalse(store.isSending)
        XCTAssertEqual(store.messages.last?.text, "First second third")
    }

    func testDeletingActiveChatRemovesItFromPersistentSessions() async throws {
        let repository = RecordingChatSessionRepository()
        let store = ChatStore(responder: ImmediateResponder(reply: "Reply"), sessionRepository: repository)
        store.draft = "Delete this conversation"
        await store.sendDraft()
        let deletedSession = try XCTUnwrap(store.openSessions.first)

        store.delete(deletedSession)
        try await Task.sleep(for: .milliseconds(50))

        let persisted = await repository.latestSessions()
        XCTAssertFalse(store.openSessions.contains { $0.id == deletedSession.id })
        XCTAssertFalse(persisted.open.contains { $0.id == deletedSession.id })
        XCTAssertFalse(persisted.archived.contains { $0.id == deletedSession.id })
        XCTAssertFalse(store.archivedSessions.contains { $0.id == deletedSession.id })
    }

    func testBurstStreamingPersistsOnlyInitialAndCompletedSession() async throws {
        let repository = RecordingChatSessionRepository()
        let store = ChatStore(responder: BurstStreamingResponder(), sessionRepository: repository)
        store.draft = "Stream efficiently"

        await store.sendDraft()
        try await Task.sleep(for: .milliseconds(80))

        let replacementCount = await repository.replacementCount()
        XCTAssertEqual(replacementCount, 2)
    }

    func testInitialMessagePersistsWhileStreamingResponseIsStillOpen() async throws {
        let repository = RecordingChatSessionRepository()
        let store = ChatStore(responder: SlowStreamingResponder(), sessionRepository: repository)
        store.draft = "Persist before response completes"

        store.startSendingDraft()
        for _ in 0..<20 where await repository.replacementCount() == 0 {
            await Task.yield()
        }

        let replacementCount = await repository.replacementCount()
        XCTAssertEqual(replacementCount, 1)
        XCTAssertTrue(store.isSending)
        store.cancelSending()
    }
}

private struct ImmediateResponder: ChatResponder {
    let reply: String

    func respond(to prompt: String) async throws -> String {
        reply
    }
}

private final class RecordingResponder: ChatResponder, @unchecked Sendable {
    private(set) var lastPrompt: String?

    func respond(to prompt: String) async throws -> String {
        lastPrompt = prompt
        return "Recorded"
    }
}

private final class DelayedResponder: ChatResponder, @unchecked Sendable {
    private var continuation: CheckedContinuation<String, Never>?
    private let onStart: @Sendable () -> Void

    init(onStart: @escaping @Sendable () -> Void = {}) {
        self.onStart = onStart
    }

    func respond(to prompt: String) async throws -> String {
        let _: String = await withCheckedContinuation { continuation in
            self.continuation = continuation
            onStart()
        }
        return "Reply to \(prompt)"
    }

    func finish() {
        continuation?.resume(returning: "")
        continuation = nil
    }
}

private final class GreetingSequence {
    private var greetings: [String]

    init(_ greetings: [String]) {
        self.greetings = greetings
    }

    func next() -> String {
        greetings.removeFirst()
    }
}

private struct SlowStreamingResponder: ChatResponder {
    func respond(to prompt: String) async throws -> String { "Partial complete" }

    func stream(to prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield("Partial")
                do {
                    try await Task.sleep(for: .seconds(1))
                    continuation.yield(" complete")
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private struct NeverEndingResponder: ChatResponder {
    func respond(to prompt: String) async throws -> String { "" }

    func stream(to prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                try? await Task.sleep(for: .seconds(3_600))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private struct ProgressingSlowResponder: ChatResponder {
    func respond(to prompt: String) async throws -> String { "" }

    func stream(to prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield("First")
                try? await Task.sleep(for: .milliseconds(35))
                continuation.yield(" second")
                try? await Task.sleep(for: .milliseconds(35))
                continuation.yield(" third")
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private struct BurstStreamingResponder: ChatResponder {
    func respond(to prompt: String) async throws -> String { "" }

    func stream(to prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for _ in 0..<32 { continuation.yield("token ") }
            continuation.finish()
        }
    }
}

private actor RecordingChatSessionRepository: ChatSessionPersisting {
    private var replaceCount = 0
    private var latest = PersistedChatSessions(open: [], archived: [], pinnedSessionIDs: [])

    func replacementCount() -> Int { replaceCount }

    func latestSessions() -> PersistedChatSessions { latest }

    func load() async throws -> PersistedChatSessions {
        PersistedChatSessions(open: [], archived: [], pinnedSessionIDs: [])
    }

    func replace(open: [ChatSession], archived: [ChatSession], pinnedSessionIDs: Set<UUID>) async throws {
        replaceCount += 1
        latest = PersistedChatSessions(open: open, archived: archived, pinnedSessionIDs: pinnedSessionIDs)
    }
}
