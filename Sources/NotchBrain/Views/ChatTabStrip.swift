import SwiftUI

struct ChatTabStrip: View {
    @ObservedObject var store: ChatStore

    var body: some View {
        AdaptiveGlassContainer {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.openSessions) { session in
                        ChatTab(
                            store: store,
                            session: session,
                            isActive: session.id == store.activeSessionID,
                            select: { store.select(session) },
                            close: { store.close(session) }
                        )
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}
