import SwiftUI

struct ChatNavigationBar: View {
    @ObservedObject var store: ChatStore
    @State private var isHistoryPresented = false

    var body: some View {
        HStack(spacing: 10) {
            ChatTabStrip(store: store)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .clipped()

            HStack(spacing: 10) {
                Divider()
                    .frame(height: 18)

                Button("Chat history", systemImage: "clock") {
                    isHistoryPresented.toggle()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Chat history")
                .popover(isPresented: $isHistoryPresented, arrowEdge: .bottom) {
                    ChatHistoryPopover(
                        sessions: store.archivedSessions,
                        restore: restoreFromHistory,
                        clearHistory: store.clearHistory
                    )
                }

                Button("New chat", systemImage: "plus", action: store.startNewChat)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("New chat")
            }
            .fixedSize()
            .layoutPriority(1)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }

    private func restoreFromHistory(_ session: ChatSession) {
        store.restore(session)
        isHistoryPresented = false
    }
}
