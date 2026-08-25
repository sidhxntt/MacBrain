import SwiftUI

struct OllamaSetupView: View {
    @ObservedObject var store: InferenceStore

    var body: some View {
        AdaptiveGlassContainer {
            VStack(alignment: .leading, spacing: 14) {
                Label("Local AI with Ollama", systemImage: "cpu")
                    .font(.headline)

                statusContent

                if !store.availableModels.isEmpty {
                    modelSelection
                }

                if let download = store.download {
                    downloadProgress(download)
                }

                if let lastError = store.lastError {
                    Label(lastError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                HStack {
                    Button("Check local setup", systemImage: "arrow.clockwise") {
                        Task { await store.refresh() }
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
            .padding(16)
            .adaptiveGlass(role: .assistantMessage, in: RoundedRectangle(cornerRadius: 16))
        }
        .task { await store.refresh() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ollama local AI setup")
    }

    @ViewBuilder
    private var statusContent: some View {
        switch store.status {
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking Ollama on this Mac…")
                    .foregroundStyle(.secondary)
            }
        case .runtimeMissing:
            VStack(alignment: .leading, spacing: 8) {
                Text("Ollama is not running")
                    .font(.subheadline.weight(.semibold))
                Text("MacBrain uses Ollama only on this Mac. Install it, open it once, then return here to download models.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("Get Ollama for Mac", destination: URL(string: "https://ollama.com/download/mac")!)
                    .buttonStyle(.borderedProminent)
            }
        case let .unavailable(message):
            VStack(alignment: .leading, spacing: 6) {
                Label("Ollama needs attention", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .ready:
            VStack(alignment: .leading, spacing: 8) {
                Label(store.isReadyForLocalChat ? "Local AI is ready" : "Choose local models", systemImage: store.isReadyForLocalChat ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(store.isReadyForLocalChat ? .green : .primary)

                if store.missingRequiredModels.isEmpty {
                    Text("Chat and embeddings run locally through Ollama. No hosted model is used.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Recommended for this Mac: Qwen3 8B for chat and Nomic Embed Text for retrieval.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(store.missingRequiredModels) { profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName).font(.subheadline.weight(.medium))
                                Text("~\(profile.estimatedDiskGB, specifier: "%.1f") GB disk · ~\(profile.estimatedMemoryGB, specifier: "%.0f") GB memory")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Download") { store.startDownload(model: profile.rawValue) }
                                .buttonStyle(.borderedProminent)
                                .disabled(store.download != nil)
                        }
                    }
                }
            }
        }
    }

    private var modelSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Chat model", selection: $store.selectedChatModel) {
                ForEach(store.availableChatModels) { model in Text(model.name).tag(model.name) }
            }
            Picker("Embedding model", selection: $store.selectedEmbeddingModel) {
                ForEach(store.availableEmbeddingModels) { model in Text(model.name).tag(model.name) }
            }
        }
        .controlSize(.small)
    }

    private func downloadProgress(_ download: OllamaPullProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(download.status.capitalized)
                    .font(.caption.weight(.medium))
                Spacer()
                Button("Cancel", role: .cancel, action: store.cancelDownload)
                    .controlSize(.small)
            }
            if let fraction = download.fractionCompleted {
                ProgressView(value: fraction)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}
