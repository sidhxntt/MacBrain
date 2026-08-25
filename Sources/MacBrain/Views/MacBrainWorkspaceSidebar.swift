import SwiftUI

struct MacBrainWorkspaceSidebar: View {
    @Binding var selection: MainWorkspaceSection
    @ObservedObject var chatStore: ChatStore

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section {
                    Button("New Chat", systemImage: "square.and.pencil") {
                        selection = .chats
                        chatStore.startNewChat()
                    }
                    .buttonStyle(.plain)

                    ForEach(MainWorkspaceSection.primarySidebarItems) { section in
                        Label(section.title, systemImage: section.symbolName)
                            .tag(section)
                    }
                }

                Section("Recent chats") {
                    ForEach(chatStore.sidebarSessions) { session in
                        DesktopChatSessionTitle(
                            session: session,
                            chatStore: chatStore,
                            selection: $selection
                        )
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            Button {
                selection = .preferences
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Settings")
        }
    }
}
