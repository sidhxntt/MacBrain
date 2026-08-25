import SwiftUI

struct SidebarView: View {
    let presentation: SidebarPresentation
    @ObservedObject var chatStore: ChatStore
    @ObservedObject var sourceLibrary: SourceLibraryStore
    let onTogglePresentation: () -> Void
    @State private var isSourceManagerPresented = false

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                sidebarShape
                    .fill(.clear)
                    .frame(width: geometry.size.width + 32, height: geometry.size.height)
                    .adaptiveGlass(role: .shell, in: sidebarShape)
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    ChatNavigationBar(store: chatStore)
                        .frame(minWidth: 0, maxWidth: .infinity)

                    Button(
                        presentation == .compact ? "Expand sidebar" : "Compact sidebar",
                        systemImage: presentation == .compact
                            ? "arrow.up.left.and.arrow.down.right"
                            : "arrow.down.right.and.arrow.up.left",
                        action: onTogglePresentation
                    )
                    .labelStyle(.iconOnly)
                    .fixedSize()
                    .layoutPriority(1)
                    .help(presentation == .compact ? "Expand sidebar" : "Compact sidebar")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()
                    .overlay(.white.opacity(0.12))

                ChatConversationView(store: chatStore)

                Label("MacBrain stays local to your Mac", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .padding(.bottom, 10)

                ChatComposer(
                    store: chatStore,
                    onClear: chatStore.clear,
                    onManageSources: { isSourceManagerPresented = true }
                )
            }
        }
        .frame(minWidth: SidebarGeometry.minimumWidth, minHeight: SidebarGeometry.minimumHeight)
        .clipShape(sidebarShape)
        .sheet(isPresented: $isSourceManagerPresented) {
            SourceManagerView(store: sourceLibrary)
        }
    }

    private var sidebarShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 24,
                bottomLeading: 24,
                bottomTrailing: 0,
                topTrailing: 0
            ),
            style: .continuous
        )
    }
}
