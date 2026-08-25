import Foundation

enum BrowserProfileEngine: String, Codable, Equatable, Sendable {
    case chromium
    case firefox
    case safari
    case webKit
    case unknown
}

enum BrowserProfileLayout: Sendable {
    case chromiumProfiles
    case firefoxProfiles
    case singleRoot
    case unavailable
}

struct BrowserProfileDefinition: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let engine: BrowserProfileEngine
    let appBundleIdentifiers: [String]
    let candidateApplicationPaths: [String]
    let profileRootRelativePaths: [String]
    let layout: BrowserProfileLayout

    var canDiscoverProfiles: Bool {
        profileRootRelativePaths.isEmpty == false && layout != .unavailable
    }

    static func == (lhs: BrowserProfileDefinition, rhs: BrowserProfileDefinition) -> Bool {
        lhs.id == rhs.id
    }
}

struct DetectedBrowserProfile: Identifiable, Equatable, Sendable {
    let browserIdentifier: String
    let browserDisplayName: String
    let engine: BrowserProfileEngine
    let profileURL: URL
    let profileDisplayName: String
    let appBundleIdentifiers: [String]
    let candidateApplicationPaths: [String]

    var id: String { "\(browserIdentifier):\(profileURL.path)" }

    var browserKind: BrowserKind? {
        BrowserKind(rawValue: browserIdentifier)
    }
}

protocol BrowserProfileFileSystem: Sendable {
    func directoryExists(at url: URL) -> Bool
    func fileExists(at url: URL) -> Bool
    func directoryContents(at url: URL) throws -> [URL]
}

struct SystemBrowserProfileFileSystem: BrowserProfileFileSystem {
    func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func directoryContents(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { candidate in
            (try? candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }
}

/// Catalog discovers known browser roots plus high-confidence Chromium layouts.
/// It never opens a browser or starts a sync operation.
struct BrowserProfileCatalog: Sendable {
    static let defaultDefinitions: [BrowserProfileDefinition] = [
        browser("safari", "Safari", .safari, ["com.apple.Safari"], ["Safari.app"], ["Library/Safari"], .singleRoot),
        browser("chrome", "Chrome", .chromium, ["com.google.Chrome"], ["Google Chrome.app"], ["Library/Application Support/Google/Chrome"], .chromiumProfiles),
        browser("chrome-canary", "Chrome Canary", .chromium, ["com.google.Chrome.canary"], ["Google Chrome Canary.app"], ["Library/Application Support/Google/Chrome Canary"], .chromiumProfiles),
        browser("chromium", "Chromium", .chromium, ["org.chromium.Chromium"], ["Chromium.app"], ["Library/Application Support/Chromium"], .chromiumProfiles),
        browser("brave", "Brave", .chromium, ["com.brave.Browser"], ["Brave Browser.app"], ["Library/Application Support/BraveSoftware/Brave-Browser"], .chromiumProfiles),
        browser("brave-beta", "Brave Beta", .chromium, ["com.brave.Browser.beta"], ["Brave Browser Beta.app"], ["Library/Application Support/BraveSoftware/Brave-Browser-Beta"], .chromiumProfiles),
        browser("brave-nightly", "Brave Nightly", .chromium, ["com.brave.Browser.nightly"], ["Brave Browser Nightly.app"], ["Library/Application Support/BraveSoftware/Brave-Browser-Nightly"], .chromiumProfiles),
        browser("opera", "Opera", .chromium, ["com.operasoftware.Opera"], ["Opera.app"], ["Library/Application Support/com.operasoftware.Opera", "Library/Application Support/com.operasoftware.Opera/Opera Stable"], .chromiumProfiles),
        browser("opera-gx", "Opera GX", .chromium, ["com.operasoftware.OperaGX"], ["Opera GX.app"], ["Library/Application Support/com.operasoftware.OperaGX"], .chromiumProfiles),
        browser("firefox", "Firefox", .firefox, ["org.mozilla.firefox"], ["Firefox.app"], ["Library/Application Support/Firefox/Profiles"], .firefoxProfiles),
        browser("firefox-developer-edition", "Firefox Developer Edition", .firefox, ["org.mozilla.firefoxdeveloperedition"], ["Firefox Developer Edition.app"], ["Library/Application Support/Firefox Developer Edition/Profiles"], .firefoxProfiles),
        browser("firefox-nightly", "Firefox Nightly", .firefox, ["org.mozilla.nightly"], ["Firefox Nightly.app"], ["Library/Application Support/Firefox Nightly/Profiles"], .firefoxProfiles),
        browser("arc", "Arc", .chromium, ["company.thebrowser.Browser"], ["Arc.app"], ["Library/Application Support/Arc/User Data"], .chromiumProfiles),
        browser("dia", "Dia", .chromium, ["company.thebrowser.dia"], ["Dia.app"], ["Library/Application Support/Dia/User Data"], .chromiumProfiles),
        browser("vivaldi", "Vivaldi", .chromium, ["com.vivaldi.Vivaldi"], ["Vivaldi.app"], ["Library/Application Support/Vivaldi"], .chromiumProfiles),
        browser("edge", "Microsoft Edge", .chromium, ["com.microsoft.edgemac"], ["Microsoft Edge.app"], ["Library/Application Support/Microsoft Edge"], .chromiumProfiles),
        browser("edge-beta", "Microsoft Edge Beta", .chromium, ["com.microsoft.edgemac.Beta"], ["Microsoft Edge Beta.app"], ["Library/Application Support/Microsoft Edge Beta"], .chromiumProfiles),
        browser("edge-dev", "Microsoft Edge Dev", .chromium, ["com.microsoft.edgemac.Dev"], ["Microsoft Edge Dev.app"], ["Library/Application Support/Microsoft Edge Dev"], .chromiumProfiles),
        browser("edge-canary", "Microsoft Edge Canary", .chromium, ["com.microsoft.edgemac.Canary"], ["Microsoft Edge Canary.app"], ["Library/Application Support/Microsoft Edge Canary"], .chromiumProfiles),
        browser("orion", "Orion", .webKit, ["com.kagi.kagimacOS"], ["Orion.app"], [], .unavailable),
        browser("duckduckgo", "DuckDuckGo", .webKit, ["com.duckduckgo.macos.browser"], ["DuckDuckGo.app"], [], .unavailable),
        browser("tor-browser", "Tor Browser", .firefox, ["org.torproject.torbrowser"], ["Tor Browser.app"], [], .unavailable)
    ]

    let homeURL: URL
    let fileSystem: any BrowserProfileFileSystem
    let definitions: [BrowserProfileDefinition]

    init(
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileSystem: any BrowserProfileFileSystem = SystemBrowserProfileFileSystem(),
        definitions: [BrowserProfileDefinition] = Self.defaultDefinitions
    ) {
        self.homeURL = homeURL
        self.fileSystem = fileSystem
        self.definitions = definitions
    }

    func detectedProfiles() throws -> [DetectedBrowserProfile] {
        var profiles: [DetectedBrowserProfile] = []
        var seenProfilePaths = Set<String>()

        for definition in definitions where definition.canDiscoverProfiles {
            for relativePath in definition.profileRootRelativePaths {
                let rootURL = homeURL.appendingPathComponent(relativePath, isDirectory: true)
                let profileURLs = try profileURLs(for: definition, rootURL: rootURL)
                for profileURL in profileURLs where seenProfilePaths.insert(profileURL.path).inserted {
                    profiles.append(
                        DetectedBrowserProfile(
                            browserIdentifier: definition.id,
                            browserDisplayName: definition.displayName,
                            engine: definition.engine,
                            profileURL: profileURL,
                            profileDisplayName: profileDisplayName(for: definition, profileURL: profileURL),
                            appBundleIdentifiers: definition.appBundleIdentifiers,
                            candidateApplicationPaths: definition.candidateApplicationPaths
                        )
                    )
                }
            }
        }

        for profile in try genericChromiumProfiles(excluding: seenProfilePaths) where seenProfilePaths.insert(profile.profileURL.path).inserted {
            profiles.append(profile)
        }

        return profiles
    }

    private func genericChromiumProfiles(excluding knownProfilePaths: Set<String>) throws -> [DetectedBrowserProfile] {
        let applicationSupport = homeURL.appendingPathComponent("Library/Application Support", isDirectory: true)
        guard fileSystem.directoryExists(at: applicationSupport) else { return [] }

        let candidates = try descendantDirectories(in: applicationSupport, depth: 0, maximumDepth: 4)
        return candidates.compactMap { profileURL in
            guard
                isChromiumProfileDirectory(profileURL.lastPathComponent),
                !knownProfilePaths.contains(profileURL.path),
                isChromiumProfileSignature(profileURL)
            else { return nil }

            return DetectedBrowserProfile(
                browserIdentifier: BrowserKind.genericChromium.rawValue,
                browserDisplayName: inferredBrowserName(for: profileURL),
                engine: .chromium,
                profileURL: profileURL,
                profileDisplayName: profileURL.lastPathComponent,
                appBundleIdentifiers: [],
                candidateApplicationPaths: []
            )
        }
    }

    private func descendantDirectories(in directory: URL, depth: Int, maximumDepth: Int) throws -> [URL] {
        guard depth < maximumDepth else { return [] }
        guard let contents = try? fileSystem.directoryContents(at: directory) else { return [] }

        var directories = contents
        for child in contents {
            directories += try descendantDirectories(in: child, depth: depth + 1, maximumDepth: maximumDepth)
        }
        return directories
    }

    private func isChromiumProfileSignature(_ profileURL: URL) -> Bool {
        ["History", "Bookmarks", "Preferences"].contains {
            fileSystem.fileExists(at: profileURL.appendingPathComponent($0))
        }
    }

    private func inferredBrowserName(for profileURL: URL) -> String {
        let parent = profileURL.deletingLastPathComponent()
        let browserDirectory = parent.lastPathComponent == "User Data" ? parent.deletingLastPathComponent() : parent
        return browserDirectory.lastPathComponent.replacingOccurrences(of: "-", with: " ")
    }

    private func profileURLs(for definition: BrowserProfileDefinition, rootURL: URL) throws -> [URL] {
        switch definition.layout {
        case .singleRoot:
            return fileSystem.directoryExists(at: rootURL) ? [rootURL] : []
        case .chromiumProfiles:
            return try directoryContentsIfAvailable(at: rootURL).filter { isChromiumProfileDirectory($0.lastPathComponent) }
        case .firefoxProfiles:
            return try directoryContentsIfAvailable(at: rootURL)
        case .unavailable:
            return []
        }
    }

    private func directoryContentsIfAvailable(at url: URL) throws -> [URL] {
        guard fileSystem.directoryExists(at: url) || (try? fileSystem.directoryContents(at: url).isEmpty == false) == true else {
            return []
        }
        return try fileSystem.directoryContents(at: url).sorted { lhs, rhs in
            chromiumProfileSortKey(lhs.lastPathComponent) < chromiumProfileSortKey(rhs.lastPathComponent)
        }
    }

    private func isChromiumProfileDirectory(_ name: String) -> Bool {
        name == "Default" || name == "Guest Profile" || name == "System Profile" || name.hasPrefix("Profile ")
    }

    private func chromiumProfileSortKey(_ name: String) -> (Int, String) {
        switch name {
        case "Default": (0, name)
        case let value where value.hasPrefix("Profile "): (1, value)
        case "Guest Profile": (2, name)
        case "System Profile": (3, name)
        default: (4, name)
        }
    }

    private func profileDisplayName(for definition: BrowserProfileDefinition, profileURL: URL) -> String {
        definition.layout == .singleRoot ? definition.displayName : profileURL.lastPathComponent
    }

    private static func browser(
        _ id: String,
        _ displayName: String,
        _ engine: BrowserProfileEngine,
        _ bundleIDs: [String],
        _ appNames: [String],
        _ profileRoots: [String],
        _ layout: BrowserProfileLayout
    ) -> BrowserProfileDefinition {
        BrowserProfileDefinition(
            id: id,
            displayName: displayName,
            engine: engine,
            appBundleIdentifiers: bundleIDs,
            candidateApplicationPaths: appNames.map { "/Applications/\($0)" },
            profileRootRelativePaths: profileRoots,
            layout: layout
        )
    }
}
