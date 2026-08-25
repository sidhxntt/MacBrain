import SwiftUI
import UniformTypeIdentifiers

struct MemoryManagerView: View {
    @ObservedObject var store: MemoryStore
    @State private var newMemory = ""
    @State private var editingMemory: StoredMemory?
    @State private var editText = ""
    @State private var showingDeleteAllConfirmation = false
    @State private var exportDocument: MemoryExportDocument?
    @State private var isExportPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Saved memories").font(.title2.weight(.semibold))
            Text("Only items you explicitly save appear here. Indexed source material is never converted into a memory.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Save a durable memory", text: $newMemory)
                Button("Save") { let value = newMemory; newMemory = ""; Task { await store.save(value) } }
                    .disabled(newMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            List(store.memories) { memory in
                VStack(alignment: .leading, spacing: 6) {
                    Text(memory.text).textSelection(.enabled)
                    Text(memory.updatedAt, style: .date).font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        Button("Edit") { editingMemory = memory; editText = memory.text }
                        Button("Forget", role: .destructive) { Task { await store.forget(memory) } }
                    }.buttonStyle(.borderless)
                }
            }
            HStack {
                Menu("Export") {
                    Button("JSON") { export(.json, filename: "macbrain-memories.json") }
                    Button("Markdown") { export(.markdown, filename: "macbrain-memories.md") }
                }
                Spacer()
                Button("Delete all", role: .destructive) { showingDeleteAllConfirmation = true }.disabled(store.memories.isEmpty)
            }
            if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(20).task { await store.reload() }
        .confirmationDialog("Delete all saved memories?", isPresented: $showingDeleteAllConfirmation, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { Task { await store.deleteAllConfirmed() } }
        } message: { Text("This cannot be undone.") }
        .alert("Edit memory", isPresented: Binding(get: { editingMemory != nil }, set: { if !$0 { editingMemory = nil } })) {
            TextField("Memory", text: $editText)
            Button("Save") { if let memory = editingMemory { Task { await store.update(memory, text: editText) } }; editingMemory = nil }
            Button("Cancel", role: .cancel) { editingMemory = nil }
        }
        .fileExporter(isPresented: $isExportPresented, document: exportDocument, contentType: .data, defaultFilename: exportDocument?.filename ?? "macbrain-memories") { _ in }
    }

    private func export(_ format: MemoryExportFormat, filename: String) {
        guard let data = try? store.export(format: format) else { return }
        exportDocument = MemoryExportDocument(data: data, filename: filename)
        isExportPresented = true
    }
}

struct MemoryExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    let data: Data
    let filename: String
    init(data: Data, filename: String) { self.data = data; self.filename = filename }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data(); filename = "macbrain-memories" }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
