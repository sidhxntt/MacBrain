import SwiftUI

struct SourceManagerView: View {
    @ObservedObject var store: SourceLibraryStore
    let showsNavigationChrome: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selectedKind: SourceConnectorKind = .folder
    @State private var selectedURL: URL?
    @State private var commitRange = ""
    @State private var recordPendingDeletion: ConnectorRecord?
    @State private var selectedSourceTab: SourceOverviewTab = .connected

    init(store: SourceLibraryStore, showsNavigationChrome: Bool = true) {
        self.store = store
        self.showsNavigationChrome = showsNavigationChrome
    }

    var body: some View {
        Group {
            if showsNavigationChrome {
                NavigationStack {
                    sourceContent
                        .navigationTitle("Local sources")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done", action: dismiss.callAsFunction)
                            }
                        }
                }
                .frame(minWidth: 520, minHeight: 500)
            } else {
                sourceContent
            }
        }
        .alert("Source needs attention", isPresented: Binding(
            get: { store.alertMessage != nil },
            set: { if !$0 { store.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.alertMessage = nil }
        } message: {
            Text(store.alertMessage ?? "")
        }
        .confirmationDialog(
            "Remove this local source?",
            isPresented: Binding(
                get: { recordPendingDeletion != nil },
                set: { if !$0 { recordPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete source and indexed content", role: .destructive) {
                if let recordPendingDeletion { store.delete(recordPendingDeletion) }
                recordPendingDeletion = nil
            }
        } message: {
            Text("This removes the source configuration and all of its locally indexed documents from MacBrain.")
        }
    }

    private var sourceContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                addSourceSection
                existingSourcesSection
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var addSourceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Local connectors", systemImage: "externaldrive.badge.plus")
                .font(.headline)

            Text("Choose exactly what MacBrain can access. Nothing connects or syncs until you select a connector and confirm.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Source type", selection: $selectedKind) {
                ForEach(SourceConnectorKind.userSelectableKinds) { kind in
                    Label(kind.displayName, systemImage: kind.symbolName).tag(kind)
                }
            }
            .pickerStyle(.menu)

            Text(selectedKind.privacyDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch selectedKind {
            case .folder, .gitRepository:
                HStack {
                    Text(selectedURL?.path ?? "No local item selected")
                        .font(.caption)
                        .foregroundStyle(selectedURL == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(selectionButtonTitle) {
                        switch selectedKind {
                        case .folder:
                            selectedURL = LocalSourcePicker.chooseFolder()
                        case .gitRepository:
                            selectedURL = LocalSourcePicker.chooseGitRepository()
                        default:
                            break
                        }
                    }
                }
                if selectedKind == .gitRepository {
                    TextField("Commit range (optional)", text: $commitRange, prompt: Text("Defaults to HEAD"))
                }
            case .browserProfile:
                Label("MacBrain will find supported installed profiles after you confirm. It does not inspect unrelated apps.", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            default:
                EmptyView()
            }

            HStack {
                Spacer()
                Button(selectedKind == .browserProfile ? "Connect installed browsers" : "Connect and sync", action: addSelectedSource)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAddSource || store.isSyncing(kind: selectedKind))
            }
        }
        .padding(16)
        .adaptiveGlass(role: .composer, in: RoundedRectangle(cornerRadius: 16))
    }

    private var existingSourcesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Source overview", selection: $selectedSourceTab) {
                ForEach(SourceOverviewTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.symbolName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 380, alignment: .leading)

            if selectedSourceTab == .connected {
                connectedSourcesContent
            } else {
                syncActivityContent
            }
        }
    }

    @ViewBuilder
    private var connectedSourcesContent: some View {
        if store.records.isEmpty {
                ContentUnavailableView(
                    "No local sources",
                    systemImage: "externaldrive.badge.plus",
                    description: Text("Choose a connector above to grant MacBrain access to a specific local source.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
        } else {
            let sourceRows = stride(from: 0, to: store.records.count, by: 2).map {
                Array(store.records[$0 ..< min($0 + 2, store.records.count)])
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(sourceRows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(row) { record in
                            SourceRecordRow(
                                record: record,
                                isWorking: store.isSyncing(record),
                                sync: { store.sync(record) },
                                pause: { store.pause(record) },
                                resume: { store.resume(record) },
                                delete: { recordPendingDeletion = record }
                            )
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }

                        if row.count == 1 {
                            Color.clear
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private var syncActivityContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            SyncScheduleSummary(
                isSyncing: store.records.contains { $0.status == .syncing } || store.records.contains(where: store.isSyncing),
                nextRefresh: store.nextAutomaticRefresh
            )

            if store.syncActivity.isEmpty {
                ContentUnavailableView(
                    "No sync activity yet",
                    systemImage: "arrow.triangle.2.circlepath",
                    description: Text("Connected sources refresh automatically every five minutes while MacBrain is open."))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                let activityGroups = store.syncActivity.groupedBySource()
                let activityRows = stride(from: 0, to: activityGroups.count, by: 2).map {
                    Array(activityGroups[$0 ..< min($0 + 2, activityGroups.count)])
                }

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(activityRows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(row) { group in
                                SyncActivityGroupCard(group: group)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                            }

                            if row.count == 1 {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
        }
    }

    private var canAddSource: Bool {
        switch selectedKind {
        case .folder, .gitRepository:
            selectedURL != nil
        case .browserProfile:
            true
        default:
            true
        }
    }

    private func addSelectedSource() {
        let displayName: String
        let configuration: SourceConnectorConfiguration
        switch selectedKind {
        case .folder:
            guard let selectedURL else { return }
            displayName = selectedURL.lastPathComponent
            configuration = SourceConnectorConfiguration(localPath: selectedURL.path, securityScopedBookmark: bookmark(for: selectedURL))
        case .gitRepository:
            guard let selectedURL else { return }
            displayName = selectedURL.lastPathComponent
            configuration = SourceConnectorConfiguration(localPath: selectedURL.path, securityScopedBookmark: bookmark(for: selectedURL), commitRange: commitRange)
        case .browserProfile:
            store.connectInstalledBrowserProfiles()
            return
        default:
            displayName = selectedKind.displayName
            configuration = SourceConnectorConfiguration()
        }
        store.addAndSync(kind: selectedKind, displayName: displayName, configuration: configuration)
    }

    private var selectionButtonTitle: String {
        switch selectedKind {
        case .folder: "Choose folder"
        case .gitRepository: "Choose repository"
        case .browserProfile: "Connect installed browsers"
        default: "Choose"
        }
    }

    private func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}

private enum SourceOverviewTab: String, CaseIterable, Identifiable {
    case connected
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connected: "Connected sources"
        case .activity: "Sync activity"
        }
    }

    var symbolName: String {
        switch self {
        case .connected: "externaldrive"
        case .activity: "arrow.triangle.2.circlepath"
        }
    }
}

private struct SyncScheduleSummary: View {
    let isSyncing: Bool
    let nextRefresh: Date?

    var body: some View {
        HStack(spacing: 10) {
            if isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18)
            } else {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(isSyncing ? "Syncing local sources" : "Background sync is on")
                    .font(.subheadline.weight(.medium))
                if let nextRefresh {
                    Text("Next refresh \(nextRefresh.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Refreshes every five minutes while MacBrain is open")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .adaptiveGlass(role: .assistantMessage, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SyncActivityGroupCard: View {
    let group: SourceSyncActivityGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: group.latestActivity.state.symbolName)
                    .foregroundStyle(foregroundStyle(for: group.latestActivity.state))
                    .frame(width: 18)
                Text(group.sourceName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(group.latestActivity.timestamp.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(group.activities.prefix(4)) { activity in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(foregroundStyle(for: activity.state))
                            .frame(width: 5, height: 5)
                        Text(activity.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(activity.timestamp.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(12)
        .adaptiveGlass(role: .assistantMessage, in: RoundedRectangle(cornerRadius: 10))
    }

    private func foregroundStyle(for state: SourceSyncActivityState) -> Color {
        switch state {
        case .syncing: .accentColor
        case .completed: .green
        case .needsAttention: .orange
        }
    }
}

private struct SourceRecordRow: View {
    let record: ConnectorRecord
    let isWorking: Bool
    let sync: () -> Void
    let pause: () -> Void
    let resume: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: record.kind.symbolName)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.displayName)
                    .font(.body.weight(.medium))
                Text(statusDescription)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                if let lastError = record.lastError {
                    Text(lastError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Menu {
                if record.status == .paused {
                    Button("Resume", systemImage: "play.fill", action: resume)
                } else {
                    Button("Pause", systemImage: "pause.fill", action: pause)
                }
                Button("Sync now", systemImage: "arrow.clockwise", action: sync)
                    .disabled(isWorking || record.status == .paused)
                Divider()
                Button("Delete source", systemImage: "trash", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(12)
        .adaptiveGlass(role: .assistantMessage, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusDescription: String {
        let count = "\(record.documentCount) \(record.documentCount == 1 ? "item" : "items")"
        switch record.status {
        case .ready:
            if let sync = record.lastSuccessfulSync {
                return "Ready · \(count) · synced \(sync.formatted(.relative(presentation: .named)))"
            }
            return "Ready · \(count)"
        case .syncing: return record.syncProgress ?? "Preparing local sync…"
        case .paused: return "Paused · \(count) retained locally"
        case .needsAuthorization: return "Permission needed · \(count) retained locally"
        case .failed: return "Sync failed · \(count) retained locally"
        }
    }

    private var statusColor: Color {
        switch record.status {
        case .ready: .secondary
        case .syncing: .accentColor
        case .paused: .orange
        case .needsAuthorization, .failed: .red
        }
    }
}
