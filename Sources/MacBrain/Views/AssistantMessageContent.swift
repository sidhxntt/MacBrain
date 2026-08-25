import SwiftUI

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

    let id = UUID()
    let kind: Kind

    static func blocks(from source: String) -> [Self] {
        var blocks: [Self] = []
        var paragraphs: [String] = []

        func appendParagraph() {
            guard !paragraphs.isEmpty else { return }
            blocks.append(.init(kind: .paragraph(paragraphs.joined(separator: "\n"))))
            paragraphs.removeAll()
        }

        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                appendParagraph()
            } else if line.hasPrefix("## ") {
                appendParagraph()
                blocks.append(.init(kind: .title(String(line.dropFirst(3)))))
            } else if line.hasPrefix("### ") {
                appendParagraph()
                blocks.append(.init(kind: .section(String(line.dropFirst(4)))))
            } else if line.hasPrefix("- ") {
                appendParagraph()
                blocks.append(.init(kind: .bullet(String(line.dropFirst(2)))))
            } else {
                paragraphs.append(line)
            }
        }
        appendParagraph()
        return blocks.isEmpty ? [.init(kind: .paragraph(source))] : blocks
    }
}
