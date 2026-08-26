import Combine
import Foundation

@MainActor
final class OnboardingStore: ObservableObject {
    @Published private(set) var step: OnboardingStep = .introduction
    @Published private(set) var isPresented: Bool
    @Published private(set) var completionMode: OnboardingCompletionMode?

    private let defaults: UserDefaults

    private enum Key {
        static let completionMode = "com.macbrain.onboarding.completion-mode"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let completionMode = defaults.string(forKey: Key.completionMode)
            .flatMap(OnboardingCompletionMode.init(rawValue:))
        self.completionMode = completionMode
        self.isPresented = completionMode == nil
    }

    var canGoBack: Bool { step != .introduction }
    var canAdvance: Bool { step != .ready }

    func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    func complete(mode: OnboardingCompletionMode) {
        completionMode = mode
        defaults.set(mode.rawValue, forKey: Key.completionMode)
        isPresented = false
    }

    func reopen() {
        step = .introduction
        isPresented = true
    }
}
