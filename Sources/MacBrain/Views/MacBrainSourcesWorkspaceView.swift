import SwiftUI

struct MacBrainSourcesWorkspaceView: View {
    @ObservedObject var sourceLibrary: SourceLibraryStore

    var body: some View {
        SourceManagerView(store: sourceLibrary, showsNavigationChrome: false)
        .navigationTitle("Sources")
    }
}
