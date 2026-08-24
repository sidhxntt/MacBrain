enum AdaptiveGlassRole: Equatable, Sendable {
    case shell
    case composer
    case assistantMessage
    case userMessage
    case prominentAction

    var isInteractive: Bool {
        self == .composer || self == .prominentAction
    }

    var usesSemanticTint: Bool {
        self == .userMessage
    }

    var fallbackTintOpacity: Double {
        switch self {
        case .shell: 0
        case .composer: 0.03
        case .assistantMessage: 0.04
        case .userMessage: 0.16
        case .prominentAction: 1
        }
    }

    var outlineOpacity: Double {
        switch self {
        case .shell: 0.18
        case .composer: 0.16
        case .assistantMessage: 0.10
        case .userMessage: 0.14
        case .prominentAction: 0.20
        }
    }

    var shadowRadius: Double {
        switch self {
        case .shell: 18
        case .composer: 10
        case .assistantMessage, .userMessage: 5
        case .prominentAction: 4
        }
    }
}
