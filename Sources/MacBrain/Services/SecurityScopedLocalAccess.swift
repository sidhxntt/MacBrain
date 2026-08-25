import Foundation

struct SecurityScopedLocalAccess {
    let url: URL
    private let startedAccess: Bool

    init(configuration: SourceConnectorConfiguration) throws {
        guard let path = configuration.localPath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            throw ConnectorError.invalidConfiguration("Choose a local folder before syncing.")
        }
        let fallbackURL = URL(fileURLWithPath: path)
        guard let bookmark = configuration.securityScopedBookmark else {
            url = fallbackURL
            startedAccess = false
            return
        }

        var stale = false
        let resolvedURL = (try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )) ?? fallbackURL
        url = resolvedURL
        startedAccess = resolvedURL.startAccessingSecurityScopedResource()
    }

    func stop() {
        if startedAccess { url.stopAccessingSecurityScopedResource() }
    }
}
