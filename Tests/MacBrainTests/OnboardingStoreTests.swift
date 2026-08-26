import Foundation
import Testing
@testable import MacBrain

@MainActor
struct OnboardingStoreTests {
    @Test
    func freshInstallPresentsIntroduction() {
        let defaults = isolatedDefaults()
        let store = OnboardingStore(defaults: defaults)

        #expect(store.isPresented)
        #expect(store.step == .introduction)
        #expect(store.completionMode == nil)
    }

    @Test
    func navigationIsBoundedToFourSteps() {
        let store = OnboardingStore(defaults: isolatedDefaults())

        store.goBack()
        #expect(store.step == .introduction)
        store.advance()
        #expect(store.step == .localAI)
        store.advance()
        #expect(store.step == .sources)
        store.advance()
        #expect(store.step == .ready)
        store.advance()
        #expect(store.step == .ready)
        store.goBack()
        #expect(store.step == .sources)
    }

    @Test(arguments: [OnboardingCompletionMode.configured, .limited])
    func completionPersistsAcrossRelaunch(mode: OnboardingCompletionMode) {
        let defaults = isolatedDefaults()
        let store = OnboardingStore(defaults: defaults)

        store.complete(mode: mode)
        let relaunched = OnboardingStore(defaults: defaults)

        #expect(!store.isPresented)
        #expect(!relaunched.isPresented)
        #expect(relaunched.completionMode == mode)
    }

    @Test
    func setupCanBeReopenedWithoutClearingCompletion() {
        let defaults = isolatedDefaults()
        let store = OnboardingStore(defaults: defaults)
        store.complete(mode: .limited)

        store.reopen()

        #expect(store.isPresented)
        #expect(store.step == .introduction)
        #expect(store.completionMode == .limited)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "macbrain-onboarding-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
