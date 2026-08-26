import SwiftUI
import AppKit

struct AssistantMessageContent: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ChatResponseBlock.blocks(from: source)) { block in
                switch block.kind {
                case let .title(text):
                    Text(ChatMarkdownRenderer.render(text))
                        .font(.headline.weight(.semibold))
                        .padding(.bottom, 2)
                case let .section(text):
                    Text(ChatMarkdownRenderer.render(text))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                case let .bullet(text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(.tint)
                        Text(ChatMarkdownRenderer.render(text))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case let .paragraph(text):
                    Text(ChatMarkdownRenderer.render(text))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(ChatCitationCard.parse(from: source)) { citation in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("[\(citation.citationID)] \(citation.title)")
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                        Text(citation.sourceTypeDisplayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let url = citation.url {
                            Button("Open source", systemImage: "arrow.up.forward.app") {
                                NSWorkspace.shared.open(url)
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Source \(citation.citationID), \(citation.sourceTypeDisplayName): \(citation.title)")
            }
        }
        .textSelection(.enabled)
        .multilineTextAlignment(.leading)
    }
}

private struct ChatResponseBlock: Identifiable {
    enum Kind {
        case title(String)
        case section(String)
        case bullet(String)
        case paragraph(String)
    }

    let id: Int
    let kind: Kind

    static func blocks(from source: String) -> [Self] {
        var blocks: [Self] = []
        var paragraphs: [String] = []

        func appendBlock(_ kind: Kind) {
            blocks.append(.init(id: blocks.count, kind: kind))
        }

        func appendParagraph() {
            guard !paragraphs.isEmpty else { return }
            appendBlock(.paragraph(paragraphs.joined(separator: "\n")))
            paragraphs.removeAll()
        }

        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                appendParagraph()
            } else if line.hasPrefix("## ") {
                appendParagraph()
                appendBlock(.title(String(line.dropFirst(3))))
            } else if line.hasPrefix("### ") {
                appendParagraph()
                appendBlock(.section(String(line.dropFirst(4))))
            } else if line.hasPrefix("- ") {
                appendParagraph()
                appendBlock(.bullet(String(line.dropFirst(2))))
            } else {
                paragraphs.append(line)
            }
        }
        appendParagraph()
        return blocks.isEmpty ? [.init(id: 0, kind: .paragraph(source))] : blocks
    }
}
