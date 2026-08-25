import SwiftUI

struct ChatConversationView: View {
    @ObservedObject var store: ChatStore

    var body: some View {
        ZStack {
            if store.messages.isEmpty {
                welcome
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                conversation
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.30), value: store.messages.isEmpty)
    }

    private var welcome: some View {
        MacBrainWelcomeView(greeting: store.welcomeGreeting)
            .id(store.activeSessionID)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(store.messages) { message in
                        ChatMessageBubble(
                            message: message,
                            onRetry: message.role == .assistant ? { store.retryLastResponse() } : nil
                        )
                            .id(message.id)
                    }

                    if store.isSending {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking locally…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("MacBrain is preparing a local response")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .scrollIndicators(.automatic)
            .onChange(of: store.messages.count) { _, _ in
                guard let lastMessage = store.messages.last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }
}
