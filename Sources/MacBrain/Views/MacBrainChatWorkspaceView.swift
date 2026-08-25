import SwiftUI

struct MacBrainChatWorkspaceView: View {
    @ObservedObject var chatStore: ChatStore
    @ObservedObject var sourceLibrary: SourceLibraryStore
    @State private var isSourceManagerPresented = false
    @State private var isRenamingHeader = false
    @State private var headerTitleDraft = ""
    @FocusState private var isHeaderTitleFocused: Bool
    @State private var isClearConfirmationPresented = false

    var body: some View {
        VStack(spacing: 0) {
            ChatConversationView(store: chatStore)

            Label("MacBrain stays local to your Mac", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ChatComposer(
                store: chatStore,
                onClear: { isClearConfirmationPresented = true },
                safeguards: nil,
                onManageSources: { isSourceManagerPresented = true }
            )
        }
        .navigationTitle(isRenamingHeader ? "" : chatStore.currentTitle)
        .toolbar {
            if isRenamingHeader {
                ToolbarItem(placement: .navigation) {
                    TextField("Chat title", text: $headerTitleDraft)
                        .textFieldStyle(.plain)
                        .font(.headline)
                        .padding(.leading, 14)
                        .frame(width: 420, alignment: .leading)
                        .focused($isHeaderTitleFocused)
                        .onSubmit(commitHeaderRename)
                        .onChange(of: headerTitleDraft) { _, newTitle in
                            guard !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            chatStore.renameCurrentChat(to: newTitle)
                        }
                        .onChange(of: isHeaderTitleFocused) { _, focused in
                            if !focused { commitHeaderRename() }
                        }
                }
            }
        }
        .background {
            DesktopChatHeaderRenameMonitor(onRename: beginHeaderRename)
        }
        .sheet(isPresented: $isSourceManagerPresented) {
            SourceManagerView(store: sourceLibrary)
        }
        .confirmationDialog("Clear this conversation?", isPresented: $isClearConfirmationPresented, titleVisibility: .visible) {
            Button("Clear conversation", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.30)) { chatStore.clear() }
            }
        } message: { Text("Messages in this open chat will be removed. This cannot be undone.") }
    }

    private func beginHeaderRename() {
        guard !isRenamingHeader else { return }
        headerTitleDraft = chatStore.currentTitle
        isRenamingHeader = true
        isHeaderTitleFocused = true
    }

    private func commitHeaderRename() {
        guard isRenamingHeader else { return }
        chatStore.renameCurrentChat(to: headerTitleDraft)
        isRenamingHeader = false
    }
}
