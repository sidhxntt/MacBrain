import SwiftUI

struct OnboardingIntroductionView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                Text("MacBrain works from your Mac")
                    .font(.title2.weight(.semibold))
                Text("Connect only the sources you want. Each connector asks for its own macOS permission, builds a local searchable index, and can be removed later with its indexed content.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                OnboardingFeatureRow(
                    symbol: "checkmark.shield",
                    title: "Explicit access",
                    detail: "Nothing connects until you choose a connector and confirm it."
                )
                OnboardingFeatureRow(
                    symbol: "bolt.horizontal.circle",
                    title: "Immediate first sync",
                    detail: "Existing source content is indexed as soon as permission is available—no source edit is required."
                )
                OnboardingFeatureRow(
                    symbol: "arrow.triangle.2.circlepath",
                    title: "Fresh in the background",
                    detail: "Connected sources refresh every five minutes while MacBrain is open."
                )
            }
        }
        .frame(maxWidth: 620, alignment: .leading)
        .padding(32)
        .accessibilityElement(children: .contain)
    }
}

private struct OnboardingFeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
