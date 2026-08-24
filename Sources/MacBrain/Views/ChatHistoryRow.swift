import SwiftUI

struct ChatHistoryRow: View {
    let session: ChatSession
    let restore: () -> Void

    var body: some View {
        Button(action: restore) {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(session.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .adaptiveGlass(role: .assistantMessage, in: RoundedRectangle(cornerRadius: 11))
        .accessibilityLabel("Restore chat \(session.title)")
    }
}
