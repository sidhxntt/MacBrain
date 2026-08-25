import SwiftUI

struct ContextChipsView: View {
    @ObservedObject var safeguards: ContextSafeguards

    var body: some View {
        if !safeguards.visibleChips.isEmpty || safeguards.recoveryGuidance != nil {
            VStack(alignment: .leading, spacing: 5) {
                if !safeguards.visibleChips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(safeguards.visibleChips) { chip in
                                HStack(spacing: 4) {
                                    Text(chip.kind.title)
                                        .lineLimit(1)
                                    Button("Remove \(chip.kind.title)", systemImage: "xmark") {
                                        safeguards.remove(chip.kind)
                                    }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                                }
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                                .help("Included in the next request: \(chip.preview)")
                            }
                        }
                    }
                    Text("Visible only; clipboard and selected text expire after this request.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let guidance = safeguards.recoveryGuidance {
                    Text(guidance)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }
}
