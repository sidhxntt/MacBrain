import SwiftUI

struct MacBrainPreferencesView: View {
    let coordinator: AppCoordinator
    @State private var isSourceManagerPresented = false
    @State private var isMemoryManagerPresented = false

    var body: some View {
        Form {
            Section("Workspace") {
                Button("Open Sidebar", systemImage: "rectangle.righthalf.inset.filled") {
                    coordinator.openSidebar()
                }
                Text("Sidebar mode is optional. Your chats and enabled local sources stay shared with this desktop workspace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Local sources") {
                Button("Manage Local Sources", systemImage: "externaldrive") {
                    isSourceManagerPresented = true
                }
                Text("MacBrain processes enabled sources locally on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Memories") {
                Button("Manage Saved Memories", systemImage: "brain.head.profile") {
                    isMemoryManagerPresented = true
                }
                Text("Memories are saved only when you explicitly choose to save them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Local AI") {
                OllamaSetupView(store: coordinator.inferenceStore)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .navigationTitle("Settings")
        .sheet(isPresented: $isSourceManagerPresented) {
            SourceManagerView(store: coordinator.sourceLibrary)
        }
        .sheet(isPresented: $isMemoryManagerPresented) {
            MemoryManagerView(store: coordinator.memoryStore)
        }
    }
}
