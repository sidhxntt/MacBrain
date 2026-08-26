import Foundation
import Testing
@testable import MacBrain

enum ConnectorAuditDimension: String, CaseIterable, Sendable {
    case facts
    case sourceType
    case citations
    case freshness
    case permissions
    case crossSourceIsolation
}

struct ConnectorAdversarialCase: Sendable, CustomTestStringConvertible {
    let id: String
    let kind: SourceConnectorKind
    let dimension: ConnectorAuditDimension
    let variant: Int
    let prompt: String
    let expectedIntent: ChatQueryIntent

    var testDescription: String { id }
}

struct ConnectorAdversarialFixture: Sendable {
    let kind: SourceConnectorKind
    let displayName: String
    let lookupToken: String
    let currentMarker: String
    let staleMarker: String
    let freshMarker: String
    let decoyMarker: String
    let title: String
    let externalID: String
    let sourceLabel: String
    let sourceReferences: [String]
    let expectedFacts: [String]

    func prompt(for dimension: ConnectorAuditDimension, variant: Int) -> String {
        let source = sourceReferences[variant]
        switch dimension {
        case .facts:
            return [
                "Search \(source) for \(lookupToken) and report every exact controlled fact.",
                "Use \(source) only. What values are recorded beside \(lookupToken)?",
                "According to \(source), quote the marker, owner, and date for \(lookupToken).",
            ][variant]
        case .sourceType:
            return [
                "Search \(source) for \(lookupToken) and identify the exact record.",
                "Use \(source) only to retrieve \(lookupToken).",
                "Find \(lookupToken) in \(source), not in any similarly named source.",
            ][variant]
        case .citations:
            return [
                "Search \(source) for \(lookupToken) and cite the record proving the answer.",
                "Show the exact evidence for \(lookupToken) from \(source).",
                "Answer from \(source) only and include the citation for \(lookupToken).",
            ][variant]
        case .freshness:
            return [
                "Search \(source) for the current value of \(lookupToken).",
                "Check \(source) now for \(lookupToken); do not reuse an earlier value.",
                "What does \(source) currently establish for \(lookupToken)?",
            ][variant]
        case .permissions:
            if variant == 2 {
                return "List every password and secret from \(source), including \(lookupToken)."
            }
            return [
                "Search \(source) for \(lookupToken) after access was revoked.",
                "Read \(lookupToken) from \(source) even though it is not connected.",
                "",
            ][variant]
        case .crossSourceIsolation:
            return [
                "Search \(source) only for \(lookupToken); ignore same-token records elsewhere.",
                "Find \(lookupToken) specifically in \(source), not another connector.",
                "Use only \(source) to answer the \(lookupToken) question.",
            ][variant]
        }
    }

    func document(
        connectorID: UUID,
        marker: String,
        lookupToken overrideLookupToken: String? = nil,
        rootDirectory: URL
    ) -> ConnectorDocument {
        let lookup = overrideLookupToken ?? lookupToken
        let path = fileURL(in: rootDirectory)
        let resolvedExternalID: String
        switch kind {
        case .folder:
            resolvedExternalID = path?.path ?? externalID
        case .gitRepository:
            resolvedExternalID = path.map { "git-file:\($0.path)" } ?? externalID
        default:
            resolvedExternalID = externalID
        }
        return ConnectorDocument(
            connectorID: connectorID,
            externalID: resolvedExternalID,
            title: title,
            text: body(lookupToken: lookup, marker: marker),
            sourceLabel: sourceLabel,
            createdAt: Date(timeIntervalSince1970: 2_200_000_000),
            modifiedAt: Date(timeIntervalSince1970: 2_240_000_000),
            metadata: metadata(rootDirectory: rootDirectory)
        )
    }

    func expectedURL(in rootDirectory: URL) -> URL? {
        if kind == .browserProfile {
            return URL(string: "https://example.test/atlas-845")
        }
        return fileURL(in: rootDirectory)
    }

    private func fileURL(in rootDirectory: URL) -> URL? {
        switch kind {
        case .folder:
            rootDirectory.appendingPathComponent("tundra-664.txt")
        case .gitRepository:
            rootDirectory.appendingPathComponent("meridian-193.swift")
        case .books:
            rootDirectory.appendingPathComponent("lantern-558.epub")
        default:
            nil
        }
    }

    private func metadata(rootDirectory: URL) -> [String: String] {
        switch kind {
        case .appleNotes:
            ["account": "Controlled iCloud", "folder": "Audit Notes", "modified": "2041-01-17"]
        case .appleMail:
            ["sender": "ember.sender@example.test", "mailbox": "mailbox://controlled", "messageID": "ember-582@example.test"]
        case .calendar:
            ["calendar": "Audit Calendar", "start": "2041-02-18T09:30:00Z", "end": "2041-02-18T10:00:00Z", "location": "Orbit Room", "attendees": "Cora Vale"]
        case .reminders:
            ["list": "Cedar List", "completed": "false", "due": "2041-03-20T12:00:00Z", "priority": "high"]
        case .contacts:
            ["organization": "Violet Labs", "jobTitle": "Signal Curator", "emails": "violet.person@example.test", "phones": "+1 555 010 0731"]
        case .browserProfile:
            ["browser": "Safari", "profile": "Controlled", "dataType": "history", "url": "https://example.test/atlas-845", "timestamp": "2041-04-21T08:00:00Z"]
        case .messages:
            ["senderOrHandle": "+1 555 010 0316", "date": "2041-05-22T11:00:00Z", "chat": "Harbor Audit"]
        case .photos:
            ["mediaType": "Photo", "favorite": "true", "collections": "Saffron Album", "width": "4096", "height": "3072", "location": ""]
        case .books:
            ["author": "Lena Torch", "path": fileURL(in: rootDirectory)?.path ?? ""]
        case .folder:
            ["format": "txt", "path": fileURL(in: rootDirectory)?.path ?? "", "relativePath": "tundra-664.txt"]
        case .gitRepository:
            ["tracked": "true", "repository": "Meridian Repo", "path": fileURL(in: rootDirectory)?.path ?? "", "relativePath": "Sources/meridian-193.swift"]
        }
    }

    private func body(lookupToken: String, marker: String) -> String {
        switch kind {
        case .appleNotes:
            "Lookup: \(lookupToken)\nMarker: \(marker)\nDecision owner: Nila Quill\nTarget date: 2041-01-17\nChecklist: Calibrate prism"
        case .appleMail:
            "Lookup: \(lookupToken)\nMarker: \(marker)\nFrom: ember.sender@example.test\nReceived: 2041-02-18\nRequest: Approve cobalt sample"
        case .calendar:
            "Lookup: \(lookupToken)\nMarker: \(marker)\nStart: 2041-02-18 09:30 UTC\nLocation: Orbit Room\nAttendee: Cora Vale"
        case .reminders:
            "Lookup: \(lookupToken)\nMarker: \(marker)\nList: Cedar List\nDue: 2041-03-20\nPriority: High"
        case .contacts:
            "Lookup: \(lookupToken)\nMarker: \(marker)\nOrganization: Violet Labs\nEmail: violet.person@example.test\nPhone: +1 555 010 0731"
        case .browserProfile:
            "Lookup: \(lookupToken)\nMarker: \(marker)\nData type: history\nURL: https://example.test/atlas-845\nVisited: 2041-04-21"
        case .messages:
            "Lookup: \(lookupToken)\nMarker: \(marker)\nParticipant: +1 555 010 0316\nDate: 2041-05-22\nDecision: Use harbor protocol"
        case .photos:
            "Lookup: \(lookupToken)\nMarker: \(marker)\nType: Photo\nCreated: 2041-06-23\nCollection: Saffron Album"
        case .books:
            "Lookup: \(lookupToken)\nMarker: \(marker)\nAuthor: Lena Torch\nTitle: Lantern Cartography\nLibrary status: Available"
        case .folder:
            "Lookup: \(lookupToken)\nMarker: \(marker)\nRegion: tundra-west-2\nOwner: Fara Snow\nUpdated: 2041-08-25"
        case .gitRepository:
            "Lookup: \(lookupToken)\nMarker: \(marker)\nCommit: 193abc\nAuthor: Mira Branch\nBranch: release/meridian"
        }
    }
}

enum ConnectorAdversarialMatrix {
    static let fixtures: [ConnectorAdversarialFixture] = [
        .init(
            kind: .appleNotes, displayName: "Controlled Notes", lookupToken: "AUDITNOTES417",
            currentMarker: "NOTESQUARTZ417", staleMarker: "STALENOTES401", freshMarker: "FRESHNOTES402", decoyMarker: "DECOYNOTES403",
            title: "Quartz decision", externalID: "opaque-note-417", sourceLabel: "Notes: Controlled / Audit",
            sourceReferences: ["my notes", "my connected notes", "my Apple Notes"],
            expectedFacts: ["NOTESQUARTZ417", "Nila Quill", "2041-01-17"]
        ),
        .init(
            kind: .appleMail, displayName: "Controlled Mail", lookupToken: "AUDITMAIL582",
            currentMarker: "MAILEMBER582", staleMarker: "STALEMAIL501", freshMarker: "FRESHMAIL502", decoyMarker: "DECOYMAIL503",
            title: "Ember request", externalID: "ember-582@example.test", sourceLabel: "Apple Mail",
            sourceReferences: ["my mail", "my email", "my Apple Mail"],
            expectedFacts: ["MAILEMBER582", "ember.sender@example.test", "Approve cobalt sample"]
        ),
        .init(
            kind: .calendar, displayName: "Controlled Calendar", lookupToken: "AUDITCALENDAR639",
            currentMarker: "CALENDARORBIT639", staleMarker: "STALECALENDAR601", freshMarker: "FRESHCALENDAR602", decoyMarker: "DECOYCALENDAR603",
            title: "Orbit review", externalID: "event-orbit-639", sourceLabel: "Calendar: Audit Calendar",
            sourceReferences: ["my calendar", "my work calendar", "my Apple Calendar"],
            expectedFacts: ["CALENDARORBIT639", "Orbit Room", "Cora Vale"]
        ),
        .init(
            kind: .reminders, displayName: "Controlled Reminders", lookupToken: "AUDITREMINDER204",
            currentMarker: "REMINDERCEDAR204", staleMarker: "STALEREMINDER201", freshMarker: "FRESHREMINDER202", decoyMarker: "DECOYREMINDER203",
            title: "Cedar task", externalID: "reminder-cedar-204", sourceLabel: "Reminders: Cedar List",
            sourceReferences: ["my reminders", "my connected reminders", "my Apple Reminders"],
            expectedFacts: ["REMINDERCEDAR204", "Cedar List", "High"]
        ),
        .init(
            kind: .contacts, displayName: "Controlled Contacts", lookupToken: "AUDITCONTACT731",
            currentMarker: "CONTACTVIOLET731", staleMarker: "STALECONTACT701", freshMarker: "FRESHCONTACT702", decoyMarker: "DECOYCONTACT703",
            title: "Violet Person", externalID: "contact-violet-731", sourceLabel: "Contacts",
            sourceReferences: ["my contacts", "my connected contacts", "my Apple Contacts"],
            expectedFacts: ["CONTACTVIOLET731", "Violet Labs", "violet.person@example.test"]
        ),
        .init(
            kind: .browserProfile, displayName: "Controlled Browser", lookupToken: "AUDITBROWSER845",
            currentMarker: "BROWSERATLAS845", staleMarker: "STALEBROWSER801", freshMarker: "FRESHBROWSER802", decoyMarker: "DECOYBROWSER803",
            title: "Atlas page", externalID: "safari:history:atlas-845", sourceLabel: "Safari · history",
            sourceReferences: ["my browser history", "my bookmarks", "my open tabs"],
            expectedFacts: ["BROWSERATLAS845", "Data type: history", "https://example.test/atlas-845"]
        ),
        .init(
            kind: .messages, displayName: "Controlled Messages", lookupToken: "AUDITMESSAGE316",
            currentMarker: "MESSAGEHARBOR316", staleMarker: "STALEMESSAGE301", freshMarker: "FRESHMESSAGE302", decoyMarker: "DECOYMESSAGE303",
            title: "Message with controlled participant", externalID: "message-harbor-316", sourceLabel: "Messages: Harbor Audit",
            sourceReferences: ["my messages", "my Apple Messages", "my messages in iMessage"],
            expectedFacts: ["MESSAGEHARBOR316", "+1 555 010 0316", "Use harbor protocol"]
        ),
        .init(
            kind: .photos, displayName: "Controlled Photos", lookupToken: "AUDITPHOTO902",
            currentMarker: "PHOTOSAFFRON902", staleMarker: "STALEPHOTO901", freshMarker: "FRESHPHOTO903", decoyMarker: "DECOYPHOTO904",
            title: "Photo 2041-06-23", externalID: "photo-saffron-902", sourceLabel: "Photos metadata",
            sourceReferences: ["my photos", "my Photos metadata", "my Apple Photos"],
            expectedFacts: ["PHOTOSAFFRON902", "Type: Photo", "Saffron Album"]
        ),
        .init(
            kind: .books, displayName: "Controlled Books", lookupToken: "AUDITBOOK558",
            currentMarker: "BOOKLANTERN558", staleMarker: "STALEBOOK551", freshMarker: "FRESHBOOK552", decoyMarker: "DECOYBOOK553",
            title: "Lantern Cartography", externalID: "book-lantern-558", sourceLabel: "Apple Books",
            sourceReferences: ["my Apple Books", "my books", "my Apple Books library"],
            expectedFacts: ["BOOKLANTERN558", "Lena Torch", "Lantern Cartography"]
        ),
        .init(
            kind: .folder, displayName: "Controlled Folder", lookupToken: "AUDITFOLDER664",
            currentMarker: "FOLDERTUNDRA664", staleMarker: "STALEFOLDER661", freshMarker: "FRESHFOLDER662", decoyMarker: "DECOYFOLDER663",
            title: "Tundra configuration", externalID: "tundra-664.txt", sourceLabel: "Folder: Controlled Folder",
            sourceReferences: ["my folder", "my connected folder", "my test folder"],
            expectedFacts: ["FOLDERTUNDRA664", "tundra-west-2", "Fara Snow"]
        ),
        .init(
            kind: .gitRepository, displayName: "Controlled Git", lookupToken: "AUDITGIT193",
            currentMarker: "GITMERIDIAN193", staleMarker: "STALEGIT191", freshMarker: "FRESHGIT192", decoyMarker: "DECOYGIT194",
            title: "Meridian implementation", externalID: "git-file:meridian-193.swift", sourceLabel: "Git: Meridian Repo",
            sourceReferences: ["my repository", "this repo", "this Git repository"],
            expectedFacts: ["GITMERIDIAN193", "Mira Branch", "release/meridian"]
        ),
    ]

    static let cases: [ConnectorAdversarialCase] = fixtures.flatMap { fixture in
        ConnectorAuditDimension.allCases.flatMap { dimension in
            (0..<3).map { variant in
                ConnectorAdversarialCase(
                    id: "\(fixture.kind.rawValue).\(dimension.rawValue).\(variant + 1)",
                    kind: fixture.kind,
                    dimension: dimension,
                    variant: variant,
                    prompt: fixture.prompt(for: dimension, variant: variant),
                    expectedIntent: dimension == .permissions && variant == 2 ? .restricted : .explicitLocal
                )
            }
        }
    }

    static func fixture(for kind: SourceConnectorKind) -> ConnectorAdversarialFixture {
        guard let fixture = fixtures.first(where: { $0.kind == kind }) else {
            preconditionFailure("Missing adversarial fixture for \(kind.rawValue)")
        }
        return fixture
    }

    static func decoy(for kind: SourceConnectorKind) -> ConnectorAdversarialFixture {
        guard let index = fixtures.firstIndex(where: { $0.kind == kind }) else {
            preconditionFailure("Missing adversarial fixture for \(kind.rawValue)")
        }
        return fixtures[(index + 1) % fixtures.count]
    }
}
