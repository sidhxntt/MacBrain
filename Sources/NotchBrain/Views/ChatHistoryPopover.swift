import SwiftUI

struct ChatHistoryPopover: View {
    let sessions: [ChatSession]
    let restore: (ChatSession) -> Void
    let clearHistory: () -> Void

    var body: some View {
        Group {
            if sessions.isEmpty {
                VStack(spacing: 6) {
                    Label("No previous chats", systemImage: "clock")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Text("Closed chats appear here.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 220)
                .padding(.vertical, 14)
            } else {
                AdaptiveGlassContainer {
                    VStack(spacing: 10) {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(sessions) { session in
                                    ChatHistoryRow(session: session) {
                                        restore(session)
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 10)
                        }
                        .scrollIndicators(.automatic)

                        Button("Clear history", systemImage: "trash", action: clearArchivedChats)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .adaptiveGlass(role: .assistantMessage, in: RoundedRectangle(cornerRadius: 9))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 10)
                            .help("Clear history")
                    }
                    .frame(width: 260, height: 220)
                    .adaptiveGlass(role: .composer, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .padding(8)
    }

    private func clearArchivedChats() {
        withAnimation(.easeInOut(duration: 0.30)) {
            clearHistory()
        }
    }
}
