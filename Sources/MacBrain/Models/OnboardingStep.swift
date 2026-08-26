import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case introduction
    case localAI
    case sources
    case ready

    var id: Int { rawValue }
}

enum OnboardingCompletionMode: String, Sendable {
    case configured
    case limited
}
