import SwiftUI

struct ChatTitleEditor: View {
    @ObservedObject var store: ChatStore
    @State private var draftTitle = ""
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField("Chat title", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .focused($isFocused)
                    .onChange(of: draftTitle) { _, newTitle in
                        store.renameCurrentChat(to: newTitle)
                    }
                    .onSubmit(commitTitle)
                    .onExitCommand(perform: cancelEditing)
            } else {
                Text(store.currentTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: beginEditing)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Double-click to rename")
                    .accessibilityAction(named: "Rename chat", beginEditing)
            }
        }
        .onChange(of: store.currentTitle) { _, newTitle in
            guard !isEditing else { return }
            draftTitle = newTitle
        }
        .onChange(of: isFocused) { _, focused in
            if isEditing, !focused {
                commitTitle()
            }
        }
    }

    private func beginEditing() {
        draftTitle = store.currentTitle
        isEditing = true
        isFocused = true
    }

    private func commitTitle() {
        guard isEditing else { return }
        store.renameCurrentChat(to: draftTitle)
        isEditing = false
    }

    private func cancelEditing() {
        isEditing = false
    }
}
