import CryptoKit
import Foundation

struct DocumentChunker: Sendable {
    let maximumUTF16Length: Int
    let overlapUTF16Length: Int

    init(maximumUTF16Length: Int = 1_200, overlapUTF16Length: Int = 160) {
        self.maximumUTF16Length = max(1, maximumUTF16Length)
        self.overlapUTF16Length = min(max(0, overlapUTF16Length), max(0, maximumUTF16Length - 1))
    }

    func chunks(for document: StoredDocument) -> [StoredChunk] {
        let length = document.text.utf16.count
        guard length > 0 else { return [] }

        let pageNumber = document.metadata["pageNumber"].flatMap(Int.init)
        var chunks: [StoredChunk] = []
        var start = 0

        while start < length {
            let end = min(start + maximumUTF16Length, length)
            let rangeStart = String.Index(utf16Offset: start, in: document.text)
            let rangeEnd = String.Index(utf16Offset: end, in: document.text)
            let text = String(document.text[rangeStart..<rangeEnd])
            let lines = lineRange(in: document.text, start: start, end: end)
            chunks.append(
                StoredChunk(
                    id: stableIdentifier(
                        sourceID: document.sourceID,
                        externalID: document.externalID,
                        start: start,
                        end: end,
                        text: text
                    ),
                    documentID: document.id,
                    sourceID: document.sourceID,
                    text: text,
                    startOffset: start,
                    endOffset: end,
                    pageNumber: pageNumber,
                    lineStart: lines.start,
                    lineEnd: lines.end
                )
            )
            guard end < length else { break }
            start = end - overlapUTF16Length
        }
        return chunks
    }

    private func lineRange(in text: String, start: Int, end: Int) -> (start: Int, end: Int) {
        let utf16 = Array(text.utf16)
        let lower = min(max(0, start), utf16.count)
        var upper = min(max(lower, end - 1), max(0, utf16.count - 1))
        while upper > lower && (utf16[upper] == 10 || utf16[upper] == 13) {
            upper -= 1
        }
        let lineStart = 1 + utf16[..<lower].filter { $0 == 10 }.count
        let lineEnd = 1 + utf16[...upper].filter { $0 == 10 }.count
        return (lineStart, lineEnd)
    }

    private func stableIdentifier(
        sourceID: UUID,
        externalID: String,
        start: Int,
        end: Int,
        text: String
    ) -> UUID {
        let input = "\(sourceID.uuidString)|\(externalID)|\(start)|\(end)|\(text)"
        let bytes = Array(SHA256.hash(data: Data(input.utf8)))
        let uuidBytes = bytes.prefix(16)
        let value = uuidBytes.map { String(format: "%02x", $0) }.joined()
        let formatted = "\(value.prefix(8))-\(value.dropFirst(8).prefix(4))-\(value.dropFirst(12).prefix(4))-\(value.dropFirst(16).prefix(4))-\(value.dropFirst(20).prefix(12))"
        return UUID(uuidString: formatted) ?? UUID()
    }
}
