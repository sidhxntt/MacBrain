import CryptoKit
import Foundation

enum BrowserKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case safari
    case chrome
    case chromeCanary = "chrome-canary"
    case chromium
    case genericChromium = "generic-chromium"
    case brave
    case braveBeta = "brave-beta"
    case braveNightly = "brave-nightly"
    case opera
    case operaGX = "opera-gx"
    case firefox
    case firefoxDeveloperEdition = "firefox-developer-edition"
    case firefoxNightly = "firefox-nightly"
    case arc
    case dia
    case vivaldi
    case edge
    case edgeBeta = "edge-beta"
    case edgeDev = "edge-dev"
    case edgeCanary = "edge-canary"
    case orion
    case duckDuckGo = "duckduckgo"
    case torBrowser = "tor-browser"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .safari: "Safari"
        case .chrome: "Chrome"
        case .chromeCanary: "Chrome Canary"
        case .chromium: "Chromium"
        case .genericChromium: "Detected Chromium browser"
        case .brave: "Brave"
        case .braveBeta: "Brave Beta"
        case .braveNightly: "Brave Nightly"
        case .opera: "Opera"
        case .operaGX: "Opera GX"
        case .firefox: "Firefox"
        case .firefoxDeveloperEdition: "Firefox Developer Edition"
        case .firefoxNightly: "Firefox Nightly"
        case .arc: "Arc"
        case .dia: "Dia"
        case .vivaldi: "Vivaldi"
        case .edge: "Microsoft Edge"
        case .edgeBeta: "Microsoft Edge Beta"
        case .edgeDev: "Microsoft Edge Dev"
        case .edgeCanary: "Microsoft Edge Canary"
        case .orion: "Orion"
        case .duckDuckGo: "DuckDuckGo"
        case .torBrowser: "Tor Browser"
        }
    }

    var applicationName: String {
        switch self {
        case .safari: "Safari"
        case .chrome: "Google Chrome"
        case .chromeCanary: "Google Chrome Canary"
        case .chromium: "Chromium"
        case .genericChromium: "Unknown Browser"
        case .brave: "Brave Browser"
        case .braveBeta: "Brave Browser Beta"
        case .braveNightly: "Brave Browser Nightly"
        case .opera: "Opera"
        case .operaGX: "Opera GX"
        case .firefox: "Firefox"
        case .firefoxDeveloperEdition: "Firefox Developer Edition"
        case .firefoxNightly: "Firefox Nightly"
        case .arc: "Arc"
        case .dia: "Dia"
        case .vivaldi: "Vivaldi"
        case .edge: "Microsoft Edge"
        case .edgeBeta: "Microsoft Edge Beta"
        case .edgeDev: "Microsoft Edge Dev"
        case .edgeCanary: "Microsoft Edge Canary"
        case .orion: "Orion"
        case .duckDuckGo: "DuckDuckGo"
        case .torBrowser: "Tor Browser"
        }
    }

    var engine: BrowserProfileEngine {
        switch self {
        case .safari: .safari
        case .chrome, .chromeCanary, .chromium, .genericChromium, .brave, .braveBeta, .braveNightly,
             .opera, .operaGX, .arc, .vivaldi, .edge, .edgeBeta, .edgeDev, .edgeCanary:
            .chromium
        case .firefox, .firefoxDeveloperEdition, .firefoxNightly, .torBrowser:
            .firefox
        case .orion, .duckDuckGo: .webKit
        case .dia: .chromium
        }
    }
}

enum SourceConnectorKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case appleNotes
    case appleMail
    case calendar
    case reminders
    case contacts
    case browserProfile
    case messages
    case photos
    case books
    case folder
    case gitRepository

    var id: String { rawValue }

    static var userSelectableKinds: [SourceConnectorKind] {
        allCases
    }

    var supportsMultipleConnections: Bool {
        switch self {
        case .folder, .gitRepository, .browserProfile:
            true
        default:
            false
        }
    }

    var displayName: String {
        switch self {
        case .appleNotes: "Apple Notes"
        case .appleMail: "Apple Mail"
        case .calendar: "Apple Calendar"
        case .reminders: "Apple Reminders"
        case .contacts: "Apple Contacts"
        case .browserProfile: "Browser Profiles"
        case .messages: "Messages"
        case .photos: "Photos metadata"
        case .books: "Apple Books"
        case .folder: "Folder"
        case .gitRepository: "Git repository"
        }
    }

    var symbolName: String {
        switch self {
        case .appleNotes: "note.text"
        case .appleMail: "envelope"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .contacts: "person.2"
        case .browserProfile: "globe"
        case .messages: "message"
        case .photos: "photo.on.rectangle"
        case .books: "books.vertical"
        case .folder: "folder"
        case .gitRepository: "point.3.connected.trianglepath.dotted"
        }
    }

    var privacyDescription: String {
        switch self {
        case .appleNotes: "Reads Notes accounts and folders available on this Mac after macOS Automation permission."
        case .appleMail: "Reads locally available Mail accounts and mailboxes, including message metadata and body text, after macOS Automation permission."
        case .calendar: "Reads calendar events after macOS Calendar permission."
        case .reminders: "Reads reminders after macOS Reminders permission."
        case .contacts: "Reads contact names and communication fields after macOS Contacts permission."
        case .browserProfile: "After you confirm, finds installed supported browser profiles and indexes locally stored bookmarks, history, Reading List, downloads, and open tabs where each browser exposes them."
        case .messages: "Reads local Messages history. macOS Full Disk Access may be required."
        case .photos: "Reads Photos metadata only, not original photo or video files."
        case .books: "Reads local Apple Books library metadata. macOS Full Disk Access may be required."
        case .folder: "Indexes supported files recursively, including hidden and secret files. Dependency and build folders are excluded."
        case .gitRepository: "Indexes supported files recursively, including hidden and secret files, plus local Git branches, commits, and changed-file metadata. Dependency and build folders are excluded."
        }
    }

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        switch rawValue {
        case "transcript": self = .folder
        case "safari": self = .browserProfile
        default:
            guard let kind = Self(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Unknown source connector.")
            }
            self = kind
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum ConnectorStatus: String, Codable, Sendable {
    case ready
    case syncing
    case paused
    case needsAuthorization
    case failed
}

struct SourceConnectorConfiguration: Codable, Equatable, Sendable {
    var accountName: String?
    var containerName: String?
    var localPath: String?
    var securityScopedBookmark: Data?
    var browserKind: BrowserKind?
    var browserDisplayName: String?
    var browserProfileName: String?
    var commitRange: String?
    var syncOffset: Int?
    var initialSyncCompleted: Bool

    init(
        accountName: String? = nil,
        containerName: String? = nil,
        localPath: String? = nil,
        securityScopedBookmark: Data? = nil,
        browserKind: BrowserKind? = nil,
        browserDisplayName: String? = nil,
        browserProfileName: String? = nil,
        commitRange: String? = nil,
        syncOffset: Int? = nil,
        initialSyncCompleted: Bool = false
    ) {
        self.accountName = accountName
        self.containerName = containerName
        self.localPath = localPath
        self.securityScopedBookmark = securityScopedBookmark
        self.browserKind = browserKind
        self.browserDisplayName = browserDisplayName
        self.browserProfileName = browserProfileName
        self.commitRange = commitRange
        self.syncOffset = syncOffset
        self.initialSyncCompleted = initialSyncCompleted
    }

    private enum CodingKeys: String, CodingKey {
        case accountName
        case containerName
        case localPath
        case securityScopedBookmark
        case browserKind
        case browserDisplayName
        case browserProfileName
        case commitRange
        case syncOffset
        case initialSyncCompleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountName = try container.decodeIfPresent(String.self, forKey: .accountName)
        containerName = try container.decodeIfPresent(String.self, forKey: .containerName)
        localPath = try container.decodeIfPresent(String.self, forKey: .localPath)
        securityScopedBookmark = try container.decodeIfPresent(Data.self, forKey: .securityScopedBookmark)
        browserKind = try container.decodeIfPresent(BrowserKind.self, forKey: .browserKind)
        browserDisplayName = try container.decodeIfPresent(String.self, forKey: .browserDisplayName)
        browserProfileName = try container.decodeIfPresent(String.self, forKey: .browserProfileName)
        commitRange = try container.decodeIfPresent(String.self, forKey: .commitRange)
        syncOffset = try container.decodeIfPresent(Int.self, forKey: .syncOffset)
        initialSyncCompleted = try container.decodeIfPresent(Bool.self, forKey: .initialSyncCompleted) ?? false
    }
}

struct ConnectorDocument: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let connectorID: UUID
    let externalID: String
    let title: String
    let text: String
    let sourceLabel: String
    let createdAt: Date?
    let modifiedAt: Date?
    let metadata: [String: String]
    let contentHash: String

    init(
        id: UUID = UUID(),
        connectorID: UUID,
        externalID: String,
        title: String,
        text: String,
        sourceLabel: String,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.connectorID = connectorID
        self.externalID = externalID
        self.title = title
        self.text = text
        self.sourceLabel = sourceLabel
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.metadata = metadata
        self.contentHash = Self.hash(title + "\n" + text + "\n" + sourceLabel)
    }

    private static func hash(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct ConnectorRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var kind: SourceConnectorKind
    var displayName: String
    var configuration: SourceConnectorConfiguration
    var status: ConnectorStatus
    var lastSuccessfulSync: Date?
    var lastError: String?
    var documentCount: Int
    var syncProgress: String?

    init(
        id: UUID = UUID(),
        kind: SourceConnectorKind,
        displayName: String,
        configuration: SourceConnectorConfiguration,
        status: ConnectorStatus = .ready,
        lastSuccessfulSync: Date? = nil,
        lastError: String? = nil,
        documentCount: Int = 0,
        syncProgress: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.configuration = configuration
        self.status = status
        self.lastSuccessfulSync = lastSuccessfulSync
        self.lastError = lastError
        self.documentCount = documentCount
        self.syncProgress = syncProgress
    }
}

enum ConnectorError: LocalizedError, Equatable, Sendable {
    case invalidConfiguration(String)
    case permissionDenied(String)
    case sourceUnavailable(String)
    case malformedContent(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message), .permissionDenied(let message), .sourceUnavailable(let message), .malformedContent(let message), .failed(let message): message
        }
    }
}
