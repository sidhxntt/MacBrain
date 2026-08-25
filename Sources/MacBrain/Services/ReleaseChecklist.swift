import Foundation

/// A redacted readiness summary for the release workflow. It deliberately
/// reports only whether a prerequisite is available, never secret material.
struct ReleaseChecklist: Sendable {
    enum MissingPrerequisite: String, CaseIterable, Equatable, Sendable {
        case developerIDSigningIdentity
        case notaryCredentials
        case hardenedRuntime
        case privacyUsageDescriptions

        var description: String {
            switch self {
            case .developerIDSigningIdentity: "Developer ID signing identity"
            case .notaryCredentials: "notarization credentials"
            case .hardenedRuntime: "hardened runtime signature"
            case .privacyUsageDescriptions: "privacy usage descriptions"
            }
        }
    }

    let missing: [MissingPrerequisite]

    var isReadyForNotarization: Bool { missing.isEmpty }

    var description: String {
        missing.isEmpty
            ? "Release prerequisites are available."
            : "Missing release prerequisites: " + missing.map(\.description).joined(separator: ", ") + "."
    }

    static func evaluate(
        signingIdentityAvailable: Bool,
        notaryCredentialsAvailable: Bool,
        hasHardenedRuntime: Bool,
        hasPrivacyUsageDescriptions: Bool
    ) -> Self {
        var missing: [MissingPrerequisite] = []
        if !signingIdentityAvailable { missing.append(.developerIDSigningIdentity) }
        if !notaryCredentialsAvailable { missing.append(.notaryCredentials) }
        if !hasHardenedRuntime { missing.append(.hardenedRuntime) }
        if !hasPrivacyUsageDescriptions { missing.append(.privacyUsageDescriptions) }
        return Self(missing: missing)
    }
}
