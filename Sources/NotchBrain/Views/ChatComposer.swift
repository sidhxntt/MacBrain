import SwiftUI

struct ChatComposer: View {
    @ObservedObject var store: ChatStore
    let onClear: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        AdaptiveGlassContainer {
            VStack(spacing: 0) {
                TextField(
                    "",
                    text: $store.draft,
                    prompt: Text("Ask MacBrain…")
                        .foregroundStyle(.tertiary)
                )
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .focused($isFocused)
                    .padding(.horizontal, 16)
                    .frame(height: 42)
                    .accessibilityLabel("Message")
                    .onSubmit(sendMessage)

                Divider()
                    .overlay(.white.opacity(0.12))

                HStack(spacing: 12) {
                    Button("Add local source", systemImage: "plus", action: {})
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.title3)
                    .help("Add a local source (coming soon)")

                    Spacer()

                    if !store.messages.isEmpty {
                        Button("Clear conversation", systemImage: "trash", action: clearConversation)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .adaptiveGlass(role: .assistantMessage, in: RoundedRectangle(cornerRadius: 8))
                            .help("Clear conversation")
                    }

                    Button("Send message", systemImage: "arrow.up", action: sendMessage)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.body.bold())
                    .foregroundStyle(isSendDisabled ? .white.opacity(0.58) : .white)
                    .frame(width: 30, height: 30)
                    .adaptiveGlass(
                        role: .prominentAction,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                    .disabled(isSendDisabled)
                    .help("Send message")
                }
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .frame(height: 42)
            }
            .adaptiveGlass(role: .composer, in: RoundedRectangle(cornerRadius: 15))
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .onAppear { isFocused = true }
    }

    private var isSendDisabled: Bool {
        store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSending
    }

    private func sendMessage() {
        Task { await store.sendDraft() }
    }

    private func clearConversation() {
        withAnimation(.easeInOut(duration: 0.30)) {
            onClear()
        }
        isFocused = true
    }
}
