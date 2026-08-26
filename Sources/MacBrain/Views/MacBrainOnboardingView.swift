import SwiftUI

struct MacBrainOnboardingView: View {
    @ObservedObject var store: OnboardingStore
    @ObservedObject var sourceLibrary: SourceLibraryStore
    @ObservedObject var inferenceStore: InferenceStore

    private var presentation: OnboardingPagePresentation {
        OnboardingPresentation.page(for: store.step)
    }

    private var readySummary: OnboardingReadySummary {
        OnboardingPresentation.readySummary(
            records: sourceLibrary.records,
            healthBySourceID: sourceLibrary.indexHealthBySourceID
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                footer
            }
            .frame(minWidth: 760, idealWidth: 860, minHeight: 620, idealHeight: 720)
            .navigationTitle("Set up MacBrain")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilitySummary)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases) { step in
                    HStack(spacing: 6) {
                        Image(systemName: step.rawValue < store.step.rawValue
                            ? "checkmark.circle.fill"
                            : step == store.step ? "circle.inset.filled" : "circle")
                            .foregroundStyle(step.rawValue <= store.step.rawValue ? Color.accentColor : .secondary)
                        Text(stepLabel(step))
                            .font(.caption)
                            .foregroundStyle(step == store.step ? .primary : .secondary)
                    }
                    if step != .ready {
                        Rectangle()
                            .fill(.quaternary)
                            .frame(height: 1)
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: presentation.symbolName)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(presentation.title)
                        .font(.title2.weight(.semibold))
                    Text(presentation.explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var page: some View {
        switch store.step {
        case .introduction:
            ScrollView { OnboardingIntroductionView() }
        case .localAI:
            ScrollView {
                OllamaSetupView(store: inferenceStore)
                    .frame(maxWidth: 680)
                    .padding(28)
                    .frame(maxWidth: .infinity)
            }
        case .sources:
            OnboardingSourcesView(store: sourceLibrary)
        case .ready:
            OnboardingReadyView(summary: readySummary)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if store.canGoBack {
                Button("Back", systemImage: "chevron.left") {
                    store.goBack()
                }
            }

            Spacer()

            if store.step != .ready {
                Button("Continue with limited context") {
                    store.complete(mode: .limited)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Finish setup without waiting for local AI or connector indexing")
            }

            Button(presentation.primaryActionTitle, action: performPrimaryAction)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private func performPrimaryAction() {
        if store.step == .ready {
            let hasVerifiedSource = !readySummary.searchableKinds.isEmpty
                || !readySummary.emptyKinds.isEmpty
            let mode: OnboardingCompletionMode = inferenceStore.isReadyForLocalChat
                && hasVerifiedSource ? .configured : .limited
            store.complete(mode: mode)
        } else {
            store.advance()
        }
    }

    private func stepLabel(_ step: OnboardingStep) -> String {
        switch step {
        case .introduction: "Welcome"
        case .localAI: "Local AI"
        case .sources: "Sources"
        case .ready: "Ready"
        }
    }
}
