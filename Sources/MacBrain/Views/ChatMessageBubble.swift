import AppKit
import SwiftUI

struct ChatMessageBubble: View {
    let message: ChatMessage
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user { Spacer(minLength: 34) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.role == .user ? "You" : "MacBrain")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Group {
                    if message.role == .assistant {
                        AssistantMessageContent(source: message.text)
                    } else {
                        Text(message.text)
                            .textSelection(.enabled)
                    }
                }
                .font(.body)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .adaptiveGlass(
                    role: message.role == .user ? .userMessage : .assistantMessage,
                    in: RoundedRectangle(cornerRadius: 16)
                )
                if message.role == .assistant {
                    HStack(spacing: 10) {
                        Button("Copy", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.text, forType: .string)
                        }
                        if let onRetry { Button("Retry", systemImage: "arrow.clockwise", action: onRetry) }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }

            if message.role == .assistant { Spacer(minLength: 34) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.role == .user ? "You" : "MacBrain"): \(message.text)")
    }
}
