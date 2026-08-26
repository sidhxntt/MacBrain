import SwiftUI

struct DesktopChatSessionTitle: View {
    let session: ChatSession
    @ObservedObject var chatStore: ChatStore
    @Binding var selection: MainWorkspaceSection
    @State private var draftTitle = ""
    @State private var isEditing = false
    @State private var isHovering = false
    @State private var isPreviewVisible = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField("Chat title", text: $draftTitle)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit(commit)
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commit() }
                    }
            } else {
                HStack(alignment: .center, spacing: 10) {
                    Button {
                        openChat()
                    } label: {
                        DesktopScrollingChatTitle(
                            title: session.title,
                            isHovering: isHovering
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Rename", action: beginEditing)
                    }
                    .accessibilityLabel("Open chat \(session.title)")
                    .accessibilityHint("Use the context menu to rename")
                    .accessibilityAction(named: "Rename chat", beginEditing)

                    hoverActions
                }
                .padding(.horizontal, 12)
                .frame(height: 36, alignment: .center)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isActive ? Color.accentColor.opacity(0.24) : Color.gray.opacity(isHovering ? 0.28 : 0))
                }
                .onHover(perform: updateHoverState)
                .animation(.easeInOut(duration: 0.28), value: isHovering)
                .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                .popover(isPresented: $isPreviewVisible, arrowEdge: .leading) {
                    DesktopChatHoverPreview(session: session)
                }
            }
        }
    }

    private var hoverActions: some View {
        HStack(spacing: 12) {
            Button {
                chatStore.togglePinned(session)
            } label: {
                Image(systemName: chatStore.isPinned(session) ? "pin.slash" : "pin")
                    .rotationEffect(.degrees(-45))
            }
            .accessibilityLabel(chatStore.isPinned(session) ? "Unpin chat" : "Pin chat")
            .help(chatStore.isPinned(session) ? "Unpin chat" : "Pin chat")

            Button(role: .destructive) {
                chatStore.delete(session)
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Delete chat")
            .help("Delete chat")
        }
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(.tertiary)
        .buttonStyle(.plain)
        .padding(.trailing, 2)
        .opacity(isHovering ? 1 : 0)
        .allowsHitTesting(isHovering)
        .accessibilityHidden(!isHovering)
    }

    private var isActive: Bool {
        session.id == chatStore.activeSessionID
    }

    private func openChat() {
        chatStore.select(session)
        selection = .chats
    }

    private func beginEditing() {
        openChat()
        draftTitle = session.title
        isEditing = true
        isFocused = true
    }

    private func commit() {
        guard isEditing else { return }
        chatStore.rename(session, to: draftTitle)
        isEditing = false
    }

    private func updateHoverState(_ isHovering: Bool) {
        self.isHovering = isHovering
        isPreviewVisible = isHovering && ChatHoverPreviewPolicy.shouldShowPreview(for: session.title)
    }
}
