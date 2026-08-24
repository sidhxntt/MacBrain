import SwiftUI

struct DesktopChatHoverPreview: View {
    let session: ChatSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Text(session.title)
                    .font(.system(size: 18, weight: .medium))
                    .lineLimit(3)

                Spacer(minLength: 0)

                Image(systemName: "trash")
                    .foregroundStyle(.tertiary)
            }

            Text(ChatHoverPreviewPolicy.previewText(for: session))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                Text("MacBrain")
                Spacer()
                Text(session.updatedAt, style: .relative)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(width: 360, alignment: .leading)
        .background(.regularMaterial)
    }
}
