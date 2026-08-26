import AppKit
import Contacts
import EventKit
import Foundation
import Photos

struct CalendarConnector: SourceConnector {
    let kind: SourceConnectorKind = .calendar

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        let granted = try await ApplePermissionGate.shared.requestCalendarAccess()
        guard granted else {
            throw ConnectorError.permissionDenied(
                "Calendar permission was not granted. Enable it in System Settings, then reauthorize."
            )
        }

        let store = EKEventStore()
        let calendars = store.calendars(for: .event)
        let predicate = store.predicateForEvents(
            withStart: .distantPast, end: .distantFuture, calendars: calendars)
        return store.events(matching: predicate).map { event in
            let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
            let attendees = event.attendees?.compactMap { $0.name }.joined(separator: ", ") ?? ""
            let notes = event.notes ?? ""
            let location = event.location ?? ""
            return ConnectorDocument(
                connectorID: record.id,
                externalID: identifier,
                title: event.title ?? "Untitled event",
                text:
                    "Calendar: \(event.calendar.title)\nStart: \(event.startDate.formatted())\nEnd: \(event.endDate.formatted())\nLocation: \(location)\nAttendees: \(attendees)\n\n\(notes)",
                sourceLabel: "Calendar: \(event.calendar.title)",
                createdAt: event.creationDate,
                modifiedAt: event.lastModifiedDate,
                metadata: [
                    "calendar": event.calendar.title,
                    "start": event.startDate.ISO8601Format(),
                    "end": event.endDate.ISO8601Format(),
                    "location": location,
                    "attendees": attendees,
                    "url": event.url?.absoluteString ?? "",
                ]
            )
        }
    }
}

struct RemindersConnector: SourceConnector {
    let kind: SourceConnectorKind = .reminders

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        let granted = try await ApplePermissionGate.shared.requestRemindersAccess()
        guard granted else {
            throw ConnectorError.permissionDenied(
                "Reminders permission was not granted. Enable it in System Settings, then reauthorize."
            )
        }

        let store = EKEventStore()
        let calendars = store.calendars(for: .reminder)
        let predicate = store.predicateForReminders(in: calendars)
        return try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let documents = (reminders ?? []).map { reminder in
                    Self.document(
                        connectorID: record.id,
                        identifier: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "Untitled reminder",
                        list: reminder.calendar.title,
                        isCompleted: reminder.isCompleted,
                        dueDate: reminder.dueDateComponents?.date,
                        completionDate: reminder.completionDate,
                        priority: reminder.priority,
                        notes: reminder.notes ?? "",
                        createdAt: reminder.creationDate,
                        modifiedAt: reminder.lastModifiedDate
                    )
                }
                continuation.resume(returning: documents)
            }
        }
    }

    static func document(
        connectorID: UUID,
        identifier: String,
        title: String,
        list: String,
        isCompleted: Bool,
        dueDate: Date?,
        completionDate: Date?,
        priority: Int,
        notes: String,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil
    ) -> ConnectorDocument {
        let priorityLabel: String
        switch priority {
        case 1...4: priorityLabel = "High"
        case 5: priorityLabel = "Medium"
        case 6...9: priorityLabel = "Low"
        default: priorityLabel = "None"
        }
        return ConnectorDocument(
            connectorID: connectorID,
            externalID: identifier,
            title: title,
            text: "List: \(list)\nCompleted: \(isCompleted ? "Yes" : "No")\nDue: \(dueDate?.formatted() ?? "No due date")\nPriority: \(priorityLabel)\n\n\(notes)",
            sourceLabel: "Reminders: \(list)",
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            metadata: [
                "list": list,
                "completed": isCompleted ? "true" : "false",
                "due": dueDate?.ISO8601Format() ?? "",
                "completedAt": completionDate?.ISO8601Format() ?? "",
                "priority": priorityLabel.lowercased(),
            ]
        )
    }
}

struct ContactsConnector: SourceConnector {
    let kind: SourceConnectorKind = .contacts

    static let requiredKeyNames: [String] = [
        CNContactIdentifierKey,
        CNContactGivenNameKey,
        CNContactMiddleNameKey,
        CNContactFamilyNameKey,
        CNContactNicknameKey,
        CNContactOrganizationNameKey,
        CNContactJobTitleKey,
        CNContactEmailAddressesKey,
        CNContactPhoneNumbersKey,
        CNContactUrlAddressesKey,
    ]

    static func displayName(
        givenName: String,
        middleName: String,
        familyName: String,
        nickname: String
    ) -> String {
        let fullName = [givenName, middleName, familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return fullName.isEmpty ? nickname : fullName
    }

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        let granted = try await ApplePermissionGate.shared.requestContactsAccess()
        guard granted else {
            throw ConnectorError.permissionDenied(
                "Contacts permission was not granted. Enable it in System Settings, then reauthorize."
            )
        }

        let store = CNContactStore()
        let keys = Self.requiredKeyNames.map { $0 as CNKeyDescriptor }
        let request = CNContactFetchRequest(keysToFetch: keys)
        var documents: [ConnectorDocument] = []
        try store.enumerateContacts(with: request) { contact, _ in
            let name = Self.displayName(
                givenName: contact.givenName,
                middleName: contact.middleName,
                familyName: contact.familyName,
                nickname: contact.nickname
            )
            let emails = contact.emailAddresses.map { $0.value as String }.joined(separator: ", ")
            let phones = contact.phoneNumbers.map { $0.value.stringValue }.joined(separator: ", ")
            let urls = contact.urlAddresses.map { $0.value as String }.joined(separator: ", ")
            documents.append(
                ConnectorDocument(
                    connectorID: record.id,
                    externalID: contact.identifier,
                    title: name.isEmpty ? "Unnamed contact" : name,
                    text:
                        "Organization: \(contact.organizationName)\nRole: \(contact.jobTitle)\nEmail: \(emails)\nPhone: \(phones)\nWeb: \(urls)",
                    sourceLabel: "Contacts",
                    metadata: [
                        "organization": contact.organizationName, "jobTitle": contact.jobTitle,
                        "emails": emails, "phones": phones,
                    ]
                ))
        }
        return documents
    }
}

struct PhotosMetadataConnector: BatchedSourceConnector {
    let kind: SourceConnectorKind = .photos
    // Photo metadata is written into the local search index with each batch.
    // Keep this deliberately small so the first visible progress update is fast.
    private let batchSize = 25

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        try await syncBatch(record: record).documents
    }

    func syncBatch(record: ConnectorRecord) async throws -> ConnectorSyncBatch {
        let status = await ApplePermissionGate.shared.requestPhotosAccess()
        guard status == .authorized || status == .limited else {
            throw ConnectorError.permissionDenied("Photos permission was not granted. Enable it in System Settings, then reauthorize.")
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: options)
        let offset = record.configuration.syncOffset ?? 0
        guard offset < assets.count else {
            return ConnectorSyncBatch(documents: [], nextOffset: nil, initialSyncCompleted: true, progressDescription: "Indexed \(record.documentCount) Photos metadata")
        }
        let endIndex = min(offset + batchSize, assets.count)
        var documents: [ConnectorDocument] = []
        for index in offset..<endIndex {
            let asset = assets.object(at: index)
            let mediaType: String
            switch asset.mediaType {
            case .image: mediaType = "Photo"
            case .video: mediaType = "Video"
            case .audio: mediaType = "Audio"
            default: mediaType = "Media"
            }
            let location = asset.location.map { "\($0.coordinate.latitude),\($0.coordinate.longitude)" } ?? ""
            let title = "\(mediaType) \(asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "unknown date")"
            let collections = PhotoCollectionMembership.names(containing: asset)
            documents.append(ConnectorDocument(
                connectorID: record.id, externalID: asset.localIdentifier, title: title,
                text: "Type: \(mediaType)\nCreated: \(asset.creationDate?.formatted() ?? "Unknown")\nFavorite: \(asset.isFavorite ? "Yes" : "No")\nCollections: \(collections)\nDimensions: \(asset.pixelWidth) × \(asset.pixelHeight)\nDuration: \(asset.duration) seconds\nLocation: \(location)",
                sourceLabel: "Photos metadata", createdAt: asset.creationDate, modifiedAt: asset.modificationDate,
                metadata: ["mediaType": mediaType, "favorite": asset.isFavorite ? "true" : "false", "collections": collections, "width": "\(asset.pixelWidth)", "height": "\(asset.pixelHeight)", "location": location]
            ))
        }
        let hasMore = endIndex < assets.count
        return ConnectorSyncBatch(documents: documents, nextOffset: hasMore ? endIndex : nil, initialSyncCompleted: !hasMore, progressDescription: "Indexed \(endIndex) of \(assets.count) Photos metadata")
    }
}

enum PhotoCollectionMembership {
    static func names(containing asset: PHAsset) -> String {
        let albums = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
        let smartAlbums = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .smartAlbum, options: nil)
        var names: [String] = []
        albums.enumerateObjects { collection, _, _ in names.append(collection.localizedTitle ?? "") }
        smartAlbums.enumerateObjects { collection, _, _ in names.append(collection.localizedTitle ?? "") }
        return format(names)
    }

    static func format(_ names: [String]) -> String {
        let unique = Set(names.filter { !$0.isEmpty })
        return unique.isEmpty ? "No collection" : unique.sorted().joined(separator: ", ")
    }
}

@MainActor
private final class ApplePermissionGate {
    static let shared = ApplePermissionGate()

    private let calendarStore = EKEventStore()
    private let remindersStore = EKEventStore()
    private let contactsStore = CNContactStore()

    private init() {}

    func requestCalendarAccess() async throws -> Bool {
        guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else {
            return EKEventStore.authorizationStatus(for: .event) == .fullAccess
        }
        return try await withForegroundPermissionWindow {
            try await calendarStore.requestFullAccessToEvents()
        }
    }

    func requestRemindersAccess() async throws -> Bool {
        guard EKEventStore.authorizationStatus(for: .reminder) == .notDetermined else {
            return EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        }
        return try await withForegroundPermissionWindow {
            try await remindersStore.requestFullAccessToReminders()
        }
    }

    func requestContactsAccess() async throws -> Bool {
        guard CNContactStore.authorizationStatus(for: .contacts) == .notDetermined else {
            return CNContactStore.authorizationStatus(for: .contacts) == .authorized
        }
        return try await withForegroundPermissionWindow {
            try await contactsStore.requestAccess(for: .contacts)
        }
    }

    func requestPhotosAccess() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .notDetermined else { return current }
        return await withForegroundPermissionWindow {
            return await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private func withForegroundPermissionWindow<T: Sendable>(
        _ operation: () async throws -> T
    ) async rethrows -> T {
        let restoreAccessory = NSApp.activationPolicy() == .accessory
        if restoreAccessory {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        defer {
            if restoreAccessory {
                NSApp.setActivationPolicy(.accessory)
            }
        }
        return try await operation()
    }
}
