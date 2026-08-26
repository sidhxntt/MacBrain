import SwiftUI

struct OnboardingSourcesView: View {
    @ObservedObject var store: SourceLibraryStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("A permission is requested only after you choose its connector. The first sync starts immediately after connection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            SourceManagerView(store: store, showsNavigationChrome: false)
        }
        .task { await store.reload() }
        .accessibilityElement(children: .contain)
    }
}
