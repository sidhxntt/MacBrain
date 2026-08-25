import Foundation

protocol MemoryPersisting: Sendable {
    func load(ownerID: String) async throws -> [StoredMemory]
    func save(_ memory: StoredMemory) async throws
    func delete(id: UUID) async throws
    func deleteAll(ownerID: String) async throws
}

actor LocalMemoryRepository: MemoryPersisting {
    private let database: MacBrainDatabase

    init(database: MacBrainDatabase) {
        self.database = database
    }

    func load(ownerID: String) async throws -> [StoredMemory] {
        try await database.memories(ownerID: ownerID)
    }

    func save(_ memory: StoredMemory) async throws {
        try await database.save(memory: memory)
    }

    func delete(id: UUID) async throws {
        try await database.remove(memoryID: id)
    }

    func deleteAll(ownerID: String) async throws {
        try await database.removeAllMemories(ownerID: ownerID)
    }
}

actor UnavailableMemoryRepository: MemoryPersisting {
    func load(ownerID: String) async throws -> [StoredMemory] { [] }
    func save(_ memory: StoredMemory) async throws { throw CocoaError(.fileNoSuchFile) }
    func delete(id: UUID) async throws { throw CocoaError(.fileNoSuchFile) }
    func deleteAll(ownerID: String) async throws { throw CocoaError(.fileNoSuchFile) }
}
