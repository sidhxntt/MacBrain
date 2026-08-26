import Foundation

enum SourceQueryScope {
    static func resolve(prompt: String) -> Set<SourceConnectorKind>? {
        SourceVocabulary().scope(in: prompt)
    }
}
