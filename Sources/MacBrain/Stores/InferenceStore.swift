import Combine
import Foundation

enum LocalModelProfile: String, CaseIterable, Sendable, Identifiable {
    case balancedChat = "qwen3:8b"
    case lightweightEmbedding = "nomic-embed-text"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .balancedChat: "Qwen3 8B (recommended)"
        case .lightweightEmbedding: "Nomic Embed Text"
        }
    }

    var estimatedDiskGB: Double {
        switch self {
        case .balancedChat: 5.2
        case .lightweightEmbedding: 0.3
        }
    }

    var estimatedMemoryGB: Double {
        switch self {
        case .balancedChat: 8
        case .lightweightEmbedding: 1
        }
    }
}

@MainActor
final class InferenceStore: ObservableObject {
    @Published private(set) var status: InferenceProviderStatus = .checking
    @Published private(set) var availableModels: [InferenceModel] = []
    @Published private(set) var download: OllamaPullProgress?
    @Published private(set) var lastError: String?
    @Published var selectedChatModel: String {
        didSet { preferences.set(selectedChatModel, forKey: Keys.chatModel) }
    }
    @Published var selectedEmbeddingModel: String {
        didSet { preferences.set(selectedEmbeddingModel, forKey: Keys.embeddingModel) }
    }

    let provider: any InferenceProvider
    private let preferences: UserDefaults
    private var downloadTask: Task<Void, Never>?

    init(provider: any InferenceProvider = OllamaProvider(), preferences: UserDefaults = .standard) {
        self.provider = provider
        self.preferences = preferences
        self.selectedChatModel = preferences.string(forKey: Keys.chatModel) ?? LocalModelProfile.balancedChat.rawValue
        self.selectedEmbeddingModel = preferences.string(forKey: Keys.embeddingModel) ?? LocalModelProfile.lightweightEmbedding.rawValue
    }

    var requiredModels: [LocalModelProfile] { [.balancedChat, .lightweightEmbedding] }

    var isReadyForLocalChat: Bool {
        guard case let .ready(models) = status else { return false }
        let names = Set(models.map(\.name))
        return names.contains(selectedChatModel) && names.contains(selectedEmbeddingModel)
    }

    var missingRequiredModels: [LocalModelProfile] {
        let names = Set(availableModels.map(\.name))
        return requiredModels.filter { !names.contains($0.rawValue) }
    }

    func refresh() async {
        status = .checking
        let newStatus = await provider.status()
        status = newStatus
        if case let .ready(models) = newStatus {
            availableModels = models
            lastError = nil
        } else {
            availableModels = []
        }
    }

    func download(model: String) async {
        lastError = nil
        do {
            for try await progress in provider.pull(model: model) {
                try Task.checkCancellation()
                download = progress
            }
            download = nil
            await refresh()
        } catch is CancellationError {
            download = nil
        } catch {
            download = nil
            lastError = error.localizedDescription
        }
    }

    func startDownload(model: String) {
        guard downloadTask == nil else { return }
        downloadTask = Task { [weak self] in
            guard let self else { return }
            await self.download(model: model)
            self.downloadTask = nil
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        download = nil
    }

    private enum Keys {
        static let chatModel = "MacBrain.Ollama.selectedChatModel"
        static let embeddingModel = "MacBrain.Ollama.selectedEmbeddingModel"
    }
}
