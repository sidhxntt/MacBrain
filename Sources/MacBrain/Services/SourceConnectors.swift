import AppKit
import Foundation

protocol SourceConnector: Sendable {
    var kind: SourceConnectorKind { get }
    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument]
}

struct ConnectorSyncBatch: Sendable {
    let documents: [ConnectorDocument]
    let nextOffset: Int?
    let initialSyncCompleted: Bool
    let progressDescription: String
}

protocol BatchedSourceConnector: SourceConnector {
    func syncBatch(record: ConnectorRecord) async throws -> ConnectorSyncBatch
}

struct FileBackedSyncResult: Sendable {
    let changedDocuments: [ConnectorDocument]
    let presentExternalIDs: [String]
    let fingerprints: [String: FileFingerprint]
}

protocol FileBackedSourceConnector: SourceConnector {
    func scan(record: ConnectorRecord) async throws -> FileBackedSyncResult
}

protocol AppleScriptExecuting: Sendable {
    func execute(_ source: String) async throws -> String
}

actor AppleScriptExecutor: AppleScriptExecuting {
    func execute(_ source: String) async throws -> String {
        try await MainActor.run {
            var error: NSDictionary?
            guard let script = NSAppleScript(source: source) else {
                throw ConnectorError.failed("MacBrain could not prepare the local Automation request.")
            }
            let result = script.executeAndReturnError(&error)
            if error != nil {
                let details =
                    error?[NSAppleScript.errorMessage] as? String ?? "macOS Automation request failed."
                let errorNumber = error?[NSAppleScript.errorNumber] as? Int
                throw Self.connectorError(message: details, errorNumber: errorNumber)
            }
            return result.stringValue ?? ""
        }
    }

    nonisolated static func connectorError(message: String, errorNumber: Int?) -> ConnectorError {
        if errorNumber == -1743
            || message == "macOS Automation request failed."
            || message.localizedCaseInsensitiveContains("not authorized")
            || message.localizedCaseInsensitiveContains("not permitted")
        {
            return .permissionDenied(
                "MacBrain needs Automation permission to read this source. Open System Settings and allow access, then reauthorize."
            )
        }
        return .failed(message)
    }
}

struct AppleNotesConnector: SourceConnector {
    let kind: SourceConnectorKind = .appleNotes
    let scriptExecutor: any AppleScriptExecuting

    init(scriptExecutor: any AppleScriptExecuting = AppleScriptExecutor()) {
        self.scriptExecutor = scriptExecutor
    }

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        let selectedAccount = record.configuration.accountName?.trimmedNonEmpty ?? ""
        let selectedFolder = record.configuration.containerName?.trimmedNonEmpty ?? ""
        let script = """
            on scrub(valueText)
                set AppleScript's text item delimiters to character id 31
                set valueText to text items of valueText
                set AppleScript's text item delimiters to " "
                return valueText as text
            end scrub
            tell application "Notes"
                set outputRows to {}
                repeat with sourceAccount in every account
                    if "\(selectedAccount.appleScriptLiteral)" is "" or (name of sourceAccount as text) is "\(selectedAccount.appleScriptLiteral)" then
                        repeat with sourceFolder in every folder of sourceAccount
                            if "\(selectedFolder.appleScriptLiteral)" is "" or (name of sourceFolder as text) is "\(selectedFolder.appleScriptLiteral)" then
                                repeat with sourceNote in every note of sourceFolder
                                    set rowText to (id of sourceNote as text) & character id 30 & my scrub(name of sourceNote as text) & character id 30 & my scrub(body of sourceNote as text) & character id 30 & (modification date of sourceNote as text) & character id 30 & (name of sourceAccount as text) & character id 30 & (name of sourceFolder as text)
                                    set end of outputRows to rowText
                                end repeat
                            end if
                        end repeat
                    end if
                end repeat
                set AppleScript's text item delimiters to character id 29
                return outputRows as text
            end tell
            """
        let output = try await scriptExecutor.execute(script)
        return try ConnectorRowParser.notes(output, record: record)
    }
}

struct AppleMailConnector: BatchedSourceConnector {
    let kind: SourceConnectorKind = .appleMail
    let scriptExecutor: any AppleScriptExecuting
    // Mail serializes body retrieval through Apple events; larger batches can
    // exceed its response window and return an empty result without an error.
    private let batchSize = 10

    init(scriptExecutor: any AppleScriptExecuting = AppleScriptExecutor()) {
        self.scriptExecutor = scriptExecutor
    }

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        try await syncBatch(record: record).documents
    }

    func syncBatch(record: ConnectorRecord) async throws -> ConnectorSyncBatch {
        let selectedAccount = record.configuration.accountName?.trimmedNonEmpty ?? ""
        let selectedMailbox = record.configuration.containerName?.trimmedNonEmpty ?? ""
        let offset = record.configuration.syncOffset ?? 0
        // Older versions could save an empty Mail result as a completed initial
        // sync. A zero-document source must retry its history once instead of
        // becoming permanently incremental-only.
        let retryEmptyHistory = record.configuration.initialSyncCompleted && record.documentCount == 0
        let useIncrementalCutoff =
            record.configuration.initialSyncCompleted && record.lastSuccessfulSync != nil && !retryEmptyHistory
        let secondsSinceLastSync = useIncrementalCutoff
            ? max(0, Int(Date().timeIntervalSince(record.lastSuccessfulSync ?? .now) - 60))
            : 0
        let script = """
            on scrub(valueText)
                set AppleScript's text item delimiters to character id 31
                set valueText to text items of valueText
                set AppleScript's text item delimiters to " "
                return valueText as text
            end scrub
            with timeout of 60 seconds
            tell application "Mail"
                set outputRows to {}
                set batchOffset to \(offset)
                set maximumMessages to \(batchSize)
                set skippedMessages to 0
                set processedMessages to 0
                set shouldUseCutoff to \(useIncrementalCutoff ? "true" : "false")
                set cutoffDate to current date
                if shouldUseCutoff then
                    set cutoffDate to cutoffDate - \(secondsSinceLastSync)
                end if
                repeat with sourceAccount in every account
                    if processedMessages < maximumMessages then
                    if "\(selectedAccount.appleScriptLiteral)" is "" or (name of sourceAccount as text) is "\(selectedAccount.appleScriptLiteral)" then
                        repeat with sourceMailbox in every mailbox of sourceAccount
                            if processedMessages < maximumMessages then
                            if "\(selectedMailbox.appleScriptLiteral)" is "" or (name of sourceMailbox as text) is "\(selectedMailbox.appleScriptLiteral)" then
                                if shouldUseCutoff then
                                    set candidateMessages to (messages of sourceMailbox whose date sent is greater than cutoffDate)
                                else
                                    set candidateMessages to messages of sourceMailbox
                                end if
                                set candidateCount to count of candidateMessages
                                set startIndex to 1
                                if skippedMessages < batchOffset then
                                    set remainingToSkip to batchOffset - skippedMessages
                                    if candidateCount <= remainingToSkip then
                                        set skippedMessages to skippedMessages + candidateCount
                                    else
                                        set startIndex to remainingToSkip + 1
                                        set skippedMessages to batchOffset
                                    end if
                                else
                                    set startIndex to 1
                                end if
                                if processedMessages < maximumMessages and candidateCount >= startIndex then
                                    set remainingSlots to maximumMessages - processedMessages
                                    set endIndex to startIndex + remainingSlots - 1
                                    if endIndex > candidateCount then set endIndex to candidateCount
                                    set selectedMessages to items startIndex thru endIndex of candidateMessages
                                    repeat with sourceMessage in selectedMessages
                                        set recipientText to ""
                                        try
                                            set recipientText to address of every to recipient of sourceMessage as text
                                        end try
                                        set rowText to (id of sourceMessage as text) & character id 30 & my scrub(subject of sourceMessage as text) & character id 30 & my scrub(sender of sourceMessage as text) & character id 30 & my scrub(recipientText) & character id 30 & my scrub(content of sourceMessage as text) & character id 30 & (date sent of sourceMessage as text) & character id 30 & (message id of sourceMessage as text) & character id 30 & (name of sourceAccount as text) & character id 30 & (name of sourceMailbox as text)
                                        set end of outputRows to rowText
                                        set processedMessages to processedMessages + 1
                                    end repeat
                                end if
                            end if
                            end if
                        end repeat
                    end if
                    end if
                end repeat
                set AppleScript's text item delimiters to character id 29
                return outputRows as text
            end tell
            end timeout
            """
        let output = try await scriptExecutor.execute(script)
        let documents = try ConnectorRowParser.mail(output, record: record)
        let hasMore = documents.count == batchSize
        let nextOffset = hasMore ? offset + documents.count : nil
        let phase = useIncrementalCutoff ? "new mail" : "mail history"
        return ConnectorSyncBatch(
            documents: documents,
            nextOffset: nextOffset,
            // A transient empty AppleScript result must not lock a source into
            // incremental-only mode; retry its history on the next sync instead.
            initialSyncCompleted: useIncrementalCutoff || (!documents.isEmpty && !hasMore),
            progressDescription: "Indexed \(documents.count) \(phase) · \(offset + documents.count) total"
        )
    }
}

struct FolderConnector: FileBackedSourceConnector {
    let kind: SourceConnectorKind = .folder

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        try await scan(record: record).changedDocuments
    }

    func scan(record: ConnectorRecord) async throws -> FileBackedSyncResult {
        let access = try SecurityScopedLocalAccess(configuration: record.configuration)
        defer { access.stop() }
        guard FileManager.default.fileExists(atPath: access.url.path) else {
            throw ConnectorError.sourceUnavailable("The selected folder is no longer available.")
        }
        let scan = try LocalFileIndexer.scan(
            rootURL: access.url,
            connectorID: record.id,
            sourceLabel: "Folder: \(record.displayName)",
            knownFingerprints: record.configuration.fileFingerprints,
            excludedRelativePaths: record.configuration.excludedRelativePaths
        )
        return FileBackedSyncResult(
            changedDocuments: scan.changedDocuments,
            presentExternalIDs: scan.presentExternalIDs,
            fingerprints: scan.fingerprints
        )
    }
}

protocol GitRunning: Sendable {
    func run(arguments: [String], at repositoryURL: URL) async throws -> String
}

actor GitRunner: GitRunning {
    private let executableURL: URL

    init(executableURL: URL = URL(fileURLWithPath: "/usr/bin/git")) {
        self.executableURL = executableURL
    }

    func run(arguments: [String], at repositoryURL: URL) throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = repositoryURL
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError
        do {
            try process.run()
        } catch {
            throw ConnectorError.sourceUnavailable("Git is unavailable on this Mac.")
        }

        // `git log` can exceed a pipe buffer in an active repository. Drain it
        // before waiting, otherwise Git and the connector can wait on each other.
        let output = String(
            decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let error = String(
                decoding: standardError.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw ConnectorError.sourceUnavailable(
                error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "This folder is not a readable Git repository."
                    : "This Git repository could not be read.")
        }
        return output
    }
}

struct GitRepositoryConnector: FileBackedSourceConnector {
    let kind: SourceConnectorKind = .gitRepository
    let runner: any GitRunning

    init(runner: any GitRunning = GitRunner()) {
        self.runner = runner
    }

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        try await scan(record: record).changedDocuments
    }

    func scan(record: ConnectorRecord) async throws -> FileBackedSyncResult {
        let access = try SecurityScopedLocalAccess(configuration: record.configuration)
        defer { access.stop() }
        let repositoryURL = access.url
        let branchOutput = try await runner.run(
            arguments: ["branch", "--format=%(refname:short)"], at: repositoryURL)
        let range = record.configuration.commitRange?.trimmedNonEmpty ?? "HEAD"
        let logOutput = try await runner.run(
            arguments: [
                "log", range, "--date=iso-strict", "--format=%x1e%H%x1f%an%x1f%ae%x1f%ad%x1f%s",
                "--name-only",
            ], at: repositoryURL)
        let trackedFilesOutput = try await runner.run(
            arguments: ["ls-files", "-z"], at: repositoryURL)
        let branches = branchOutput.split(whereSeparator: \.isNewline).map(String.init).filter {
            !$0.isEmpty
        }
        let trackedPaths = Set(
            trackedFilesOutput.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        )
        let fileScan = try LocalFileIndexer.scan(
            rootURL: repositoryURL,
            connectorID: record.id,
            sourceLabel: "Git: \(record.displayName)",
            knownFingerprints: record.configuration.fileFingerprints,
            allowedRelativePaths: trackedPaths,
            excludedRelativePaths: record.configuration.excludedRelativePaths
        )
        let files = fileScan.changedDocuments.map { document in
            var metadata = document.metadata
            metadata["tracked"] = trackedPaths.contains(document.metadata["relativePath"] ?? "") ? "true" : "false"
            metadata["repository"] = record.displayName
            return ConnectorDocument(
                connectorID: document.connectorID,
                externalID: gitExternalID(document.externalID),
                title: document.title,
                text: document.text,
                sourceLabel: document.sourceLabel,
                createdAt: document.createdAt,
                modifiedAt: document.modifiedAt,
                metadata: metadata
            )
        }
        let commits = try ConnectorRowParser.git(logOutput, record: record, branches: branches)
        let fingerprints = Dictionary(uniqueKeysWithValues: fileScan.fingerprints.map { key, value in
            (
                key,
                FileFingerprint(
                    byteCount: value.byteCount,
                    modifiedAt: value.modifiedAt,
                    documentExternalIDs: value.documentExternalIDs.map(gitExternalID)
                )
            )
        })
        return FileBackedSyncResult(
            changedDocuments: files + commits,
            presentExternalIDs: fileScan.presentExternalIDs.map(gitExternalID) + commits.map(\.externalID),
            fingerprints: fingerprints
        )
    }
}

private func gitExternalID(_ externalID: String) -> String {
    externalID.hasPrefix("git-file:") ? externalID : "git-file:\(externalID)"
}

private enum ConnectorRowParser {
    static func notes(_ output: String, record: ConnectorRecord) throws -> [ConnectorDocument] {
        guard !output.isEmpty else { return [] }
        return output.split(separator: "\u{1D}").compactMap { row in
            let parts = row.split(separator: "\u{1E}", omittingEmptySubsequences: false).map(
                String.init)
            guard parts.count >= 3 else { return nil }
            return ConnectorDocument(
                connectorID: record.id,
                externalID: parts[0],
                title: parts[1].isEmpty ? "Untitled note" : parts[1],
                text: parts[2].strippingHTML,
                sourceLabel:
                    "Notes: \(parts.count > 4 ? parts[4] : record.configuration.accountName ?? "All accounts") / \(parts.count > 5 ? parts[5] : record.configuration.containerName ?? "All folders")",
                metadata: [
                    "account": parts.count > 4 ? parts[4] : record.configuration.accountName ?? "",
                    "folder": parts.count > 5 ? parts[5] : record.configuration.containerName ?? "",
                    "modified": parts.count > 3 ? parts[3] : "",
                ]
            )
        }
    }

    static func mail(_ output: String, record: ConnectorRecord) throws -> [ConnectorDocument] {
        guard !output.isEmpty else { return [] }
        return output.split(separator: "\u{1D}").compactMap { row in
            let parts = row.split(separator: "\u{1E}", omittingEmptySubsequences: false).map(
                String.init)
            guard parts.count >= 6 else { return nil }
            let subject = parts[1].isEmpty ? "No subject" : parts[1]
            let sender = parts[2]
            let recipients = parts[3]
            let body = parts[4]
            return ConnectorDocument(
                connectorID: record.id,
                externalID: parts[0],
                title: subject,
                text: "From: \(sender)\nTo: \(recipients)\n\n\(body)",
                sourceLabel:
                    "Mail: \(parts.count > 7 ? parts[7] : record.configuration.accountName ?? "All accounts") / \(parts.count > 8 ? parts[8] : record.configuration.containerName ?? "All mailboxes")",
                metadata: [
                    "sender": sender, "recipients": recipients, "sentDate": parts[5],
                    "threadID": parts.count > 6 ? parts[6] : parts[0],
                    "account": parts.count > 7 ? parts[7] : record.configuration.accountName ?? "",
                    "mailbox": parts.count > 8
                        ? parts[8] : record.configuration.containerName ?? "",
                ]
            )
        }
    }

    static func git(_ output: String, record: ConnectorRecord, branches: [String]) throws
        -> [ConnectorDocument]
    {
        output.split(separator: "\u{1E}").compactMap { commitChunk in
            let lines = commitChunk.split(whereSeparator: \.isNewline).map(String.init)
            guard let header = lines.first else { return nil }
            let fields = header.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(
                String.init)
            guard fields.count >= 5 else { return nil }
            let files = Array(lines.dropFirst()).filter { !$0.isEmpty }
            let subject = fields[4]
            let references = subject.matches(
                pattern: "(?i)(?:#\\d+|(?:issue|pr|pull request)\\s*#?\\d+)")
            return ConnectorDocument(
                connectorID: record.id,
                externalID: fields[0],
                title: subject,
                text:
                    "Commit \(fields[0])\nAuthor: \(fields[1]) <\(fields[2])>\nDate: \(fields[3])\nBranches: \(branches.joined(separator: ", "))\nChanged files:\n\(files.joined(separator: "\n"))",
                sourceLabel: "Git: \(record.displayName)",
                metadata: [
                    "commit": fields[0], "author": fields[1], "email": fields[2], "date": fields[3],
                    "branches": branches.joined(separator: ", "),
                    "changedFiles": files.joined(separator: "\n"),
                    "references": references.joined(separator: ", "),
                ]
            )
        }
    }
}

extension String {
    fileprivate var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    fileprivate var appleScriptLiteral: String {
        replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    fileprivate var strippingHTML: String {
        let fallback = replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        guard let data = data(using: .utf8),
            let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
            )
        else { return fallback }
        return attributed.string == self ? fallback : attributed.string
    }

    fileprivate func matches(pattern: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(startIndex..., in: self)
        return expression.matches(in: self, range: range).compactMap {
            Range($0.range, in: self).map { String(self[$0]) }
        }
    }
}
