import SwiftUI

struct ChatTab: View {
    @ObservedObject var store: ChatStore
    let session: ChatSession
    let isActive: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            if isActive {
                ChatTitleEditor(store: store)
                    .frame(maxWidth: 126, alignment: .leading)
            } else {
                Button(session.title, action: select)
                    .buttonStyle(.plain)
                    .lineLimit(1)
                    .frame(maxWidth: 126, alignment: .leading)
            }

            Button("Close \(session.title)", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.caption.bold())
                .help("Close \(session.title)")
        }
        .foregroundStyle(isActive ? .primary : .secondary)
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 30)
        .adaptiveGlass(
            role: isActive ? .composer : .assistantMessage,
            in: Capsule()
        )
        .accessibilityElement(children: .contain)
    }
}
