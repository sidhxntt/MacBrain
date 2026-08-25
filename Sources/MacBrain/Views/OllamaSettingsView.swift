import SwiftUI

struct OllamaSettingsView: View {
    @ObservedObject var store: InferenceStore

    var body: some View {
        ScrollView {
            OllamaSetupView(store: store)
                .padding(20)
        }
        .navigationTitle("Local AI")
    }
}
