import XCTest
@testable import MacBrain

@MainActor
final class MacBrainWorkspaceViewTests: XCTestCase {
    func testDesktopWorkspaceCanBeConstructed() {
        _ = MacBrainWorkspaceView(coordinator: AppCoordinator())
    }

    func testDesktopWorkspaceUsesOnlyNativeSplitViewToggle() {
        XCTAssertFalse(MacBrainWorkspaceView.showsCustomSidebarToggle)
    }

    func testCoordinatorSharesPersistentOnboardingStateWithWorkspace() {
        let defaults = isolatedDefaults()
        let firstRunStore = OnboardingStore(defaults: defaults)
        let firstRun = AppCoordinator(onboardingStore: firstRunStore)

        XCTAssertTrue(firstRun.onboardingStore.isPresented)
        _ = MacBrainWorkspaceView(coordinator: firstRun)

        firstRun.onboardingStore.complete(mode: .limited)
        let relaunched = AppCoordinator(
            onboardingStore: OnboardingStore(defaults: defaults)
        )

        XCTAssertFalse(relaunched.onboardingStore.isPresented)
        XCTAssertEqual(relaunched.onboardingStore.completionMode, .limited)
    }

    func testRunSetupAgainDoesNotClearConnectorRecords() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "macbrain-workspace-onboarding-" + UUID().uuidString,
            isDirectory: true
        )
        let repository = LocalSourceRepository(
            fileURL: directory.appendingPathComponent("sources.json")
        )
        let sourceLibrary = SourceLibraryStore(repository: repository, database: nil)
        let connector = ConnectorRecord(
            kind: .appleNotes,
            displayName: SourceConnectorKind.appleNotes.displayName,
            configuration: .init(initialSyncCompleted: true),
            status: .ready,
            lastSuccessfulSync: .now
        )
        try await repository.save(connector)

        let onboarding = OnboardingStore(defaults: isolatedDefaults())
        onboarding.complete(mode: .configured)
        let coordinator = AppCoordinator(
            sourceLibrary: sourceLibrary,
            onboardingStore: onboarding
        )
        let before = await repository.allRecords()

        coordinator.onboardingStore.reopen()

        let after = await repository.allRecords()
        XCTAssertTrue(coordinator.onboardingStore.isPresented)
        XCTAssertEqual(after.map(\.id), before.map(\.id))
        _ = MacBrainPreferencesView(coordinator: coordinator)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "macbrain-workspace-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
