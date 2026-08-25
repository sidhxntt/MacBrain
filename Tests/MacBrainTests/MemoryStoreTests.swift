import XCTest
@testable import MacBrain

@MainActor
final class MemoryStoreTests: XCTestCase {
    func testSaveEditForgetAndDeleteAllRequireExplicitOperations() async throws {
        let repository = InMemoryMemoryRepository()
        let store = MemoryStore(repository: repository)

        await store.reload()
        await store.save("Use local-first storage")
        XCTAssertEqual(store.memories.map(\.text), ["Use local-first storage"])

        let memory = try XCTUnwrap(store.memories.first)
        await store.update(memory, text: "Use encrypted local-first storage")
        XCTAssertEqual(store.memories.map(\.text), ["Use encrypted local-first storage"])

        await store.forget(memory)
        XCTAssertTrue(store.memories.isEmpty)

        await store.save("A")
        await store.save("B")
        XCTAssertEqual(store.memories.count, 2)
        await store.deleteAllConfirmed()
        XCTAssertTrue(store.memories.isEmpty)
    }

    func testExportIsPortableJSONAndMarkdown() async throws {
        let repository = InMemoryMemoryRepository()
        let store = MemoryStore(repository: repository)
        await store.save("Never send data to hosted APIs")

        let json = try store.export(format: .json)
        XCTAssertTrue(String(decoding: json, as: UTF8.self).contains("Never send data"))
        let markdown = try store.export(format: .markdown)
        XCTAssertTrue(String(decoding: markdown, as: UTF8.self).contains("# MacBrain Memories"))
    }
}

private actor InMemoryMemoryRepository: MemoryPersisting {
    private var values: [StoredMemory] = []

    func load(ownerID: String) async throws -> [StoredMemory] { values.filter { $0.ownerID == ownerID } }
    func save(_ memory: StoredMemory) async throws {
        if let index = values.firstIndex(where: { $0.id == memory.id }) { values[index] = memory } else { values.append(memory) }
    }
    func delete(id: UUID) async throws { values.removeAll { $0.id == id } }
    func deleteAll(ownerID: String) async throws { values.removeAll { $0.ownerID == ownerID } }
}
