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
                    let identifier = reminder.calendarItemIdentifier
                    let dueDate = reminder.dueDateComponents?.date
                    let completionDate = reminder.completionDate
                    let notes = reminder.notes ?? ""
                    return ConnectorDocument(
                        connectorID: record.id,
                        externalID: identifier,
                        title: reminder.title ?? "Untitled reminder",
                        text:
                            "List: \(reminder.calendar.title)\nCompleted: \(reminder.isCompleted ? "Yes" : "No")\nDue: \(dueDate?.formatted() ?? "No due date")\n\n\(notes)",
                        sourceLabel: "Reminders: \(reminder.calendar.title)",
                        createdAt: reminder.creationDate,
                        modifiedAt: reminder.lastModifiedDate,
                        metadata: [
                            "list": reminder.calendar.title,
                            "completed": reminder.isCompleted ? "true" : "false",
                            "due": dueDate?.ISO8601Format() ?? "",
                            "completedAt": completionDate?.ISO8601Format() ?? "",
                        ]
                    )
                }
                continuation.resume(returning: documents)
            }
        }
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

struct PhotosMetadataConnector: SourceConnector {
    let kind: SourceConnectorKind = .photos

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        let status = await ApplePermissionGate.shared.requestPhotosAccess()
        guard status == .authorized || status == .limited else {
            throw ConnectorError.permissionDenied(
                "Photos permission was not granted. Enable it in System Settings, then reauthorize."
            )
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: options)
        var documents: [ConnectorDocument] = []
        assets.enumerateObjects { asset, _, _ in
            let mediaType: String
            switch asset.mediaType {
            case .image: mediaType = "Photo"
            case .video: mediaType = "Video"
            case .audio: mediaType = "Audio"
            default: mediaType = "Media"
            }
            let location =
                asset.location.map { "\($0.coordinate.latitude),\($0.coordinate.longitude)" } ?? ""
            let title =
                "\(mediaType) \(asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "unknown date")"
            documents.append(
                ConnectorDocument(
                    connectorID: record.id,
                    externalID: asset.localIdentifier,
                    title: title,
                    text:
                        "Type: \(mediaType)\nCreated: \(asset.creationDate?.formatted() ?? "Unknown")\nFavorite: \(asset.isFavorite ? "Yes" : "No")\nDimensions: \(asset.pixelWidth) × \(asset.pixelHeight)\nDuration: \(asset.duration) seconds\nLocation: \(location)",
                    sourceLabel: "Photos metadata",
                    createdAt: asset.creationDate,
                    modifiedAt: asset.modificationDate,
                    metadata: [
                        "mediaType": mediaType, "favorite": asset.isFavorite ? "true" : "false",
                        "width": "\(asset.pixelWidth)", "height": "\(asset.pixelHeight)",
                        "location": location,
                    ]
                ))
        }
        return documents
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
        try await withForegroundPermissionWindow {
            try await calendarStore.requestFullAccessToEvents()
        }
    }

    func requestRemindersAccess() async throws -> Bool {
        try await withForegroundPermissionWindow {
            try await remindersStore.requestFullAccessToReminders()
        }
    }

    func requestContactsAccess() async throws -> Bool {
        try await withForegroundPermissionWindow {
            try await contactsStore.requestAccess(for: .contacts)
        }
    }

    func requestPhotosAccess() async -> PHAuthorizationStatus {
        await withForegroundPermissionWindow {
            let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard current == .notDetermined else { return current }
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
