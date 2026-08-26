import SwiftUI

struct OnboardingReadyView: View {
    let summary: OnboardingReadySummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                statusSection(
                    title: "Searchable now",
                    symbol: "checkmark.circle.fill",
                    color: .green,
                    kinds: summary.searchableKinds
                )
                statusSection(
                    title: "Verified, currently empty",
                    symbol: "checkmark.circle",
                    color: .secondary,
                    kinds: summary.emptyKinds
                )
                statusSection(
                    title: "Preparing first index",
                    symbol: "arrow.triangle.2.circlepath",
                    color: .accentColor,
                    kinds: summary.syncingKinds
                )
                statusSection(
                    title: "Permission needed",
                    symbol: "hand.raised.fill",
                    color: .orange,
                    kinds: summary.permissionNeededKinds
                )
                statusSection(
                    title: "Needs attention",
                    symbol: "exclamationmark.triangle.fill",
                    color: .orange,
                    kinds: summary.failedKinds
                )

                VStack(alignment: .leading, spacing: 10) {
                    Label("Try asking", systemImage: "text.bubble")
                        .font(.headline)
                    ForEach(summary.exampleQuestions, id: \.self) { question in
                        Text("“\(question)”")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(16)
                .adaptiveGlass(
                    role: .assistantMessage,
                    in: RoundedRectangle(cornerRadius: 14)
                )

                if !summary.optionalKinds.isEmpty {
                    Text("You can connect more sources later from Sources. Finishing setup does not grant any additional access.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func statusSection(
        title: String,
        symbol: String,
        color: Color,
        kinds: Set<SourceConnectorKind>
    ) -> some View {
        if !kinds.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(color)
                Text(kinds.map(\.displayName).sorted().joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
