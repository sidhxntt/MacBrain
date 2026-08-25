import Combine
import Foundation

enum MemoryExportFormat: Sendable { case json, markdown }

@MainActor
final class MemoryStore: ObservableObject {
    @Published private(set) var memories: [StoredMemory] = []
    @Published private(set) var errorMessage: String?

    private let repository: any MemoryPersisting
    private let ownerID: String

    init(repository: any MemoryPersisting, ownerID: String = "local-user") {
        self.repository = repository
        self.ownerID = ownerID
    }

    func reload() async {
        do {
            memories = try await repository.load(ownerID: ownerID)
            errorMessage = nil
        } catch {
            errorMessage = "MacBrain couldn't load local memories."
        }
    }

    func save(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let memory = StoredMemory(ownerID: ownerID, text: trimmed)
        do {
            try await repository.save(memory)
            memories.append(memory)
            memories.sort { $0.updatedAt > $1.updatedAt }
        } catch { errorMessage = "MacBrain couldn't save that memory." }
    }

    func update(_ memory: StoredMemory, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = memory
        updated.text = trimmed
        updated.updatedAt = .now
        do {
            try await repository.save(updated)
            if let index = memories.firstIndex(where: { $0.id == updated.id }) { memories[index] = updated }
        } catch { errorMessage = "MacBrain couldn't update that memory." }
    }

    func forget(_ memory: StoredMemory) async {
        do {
            try await repository.delete(id: memory.id)
            memories.removeAll { $0.id == memory.id }
        } catch { errorMessage = "MacBrain couldn't forget that memory." }
    }

    /// Call only after the UI obtains explicit destructive confirmation.
    func deleteAllConfirmed() async {
        do {
            try await repository.deleteAll(ownerID: ownerID)
            memories.removeAll()
        } catch { errorMessage = "MacBrain couldn't delete local memories." }
    }

    func export(format: MemoryExportFormat) throws -> Data {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(memories)
        case .markdown:
            let date = ISO8601DateFormatter()
            let body = memories.map { "- \($0.text)  \\n  Saved: \(date.string(from: $0.createdAt))" }.joined(separator: "\n")
            return Data(("# MacBrain Memories\n\n" + (body.isEmpty ? "No saved memories.\n" : body + "\n")).utf8)
        }
    }
}
