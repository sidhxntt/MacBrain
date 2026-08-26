import AppKit
import SwiftUI

@main
struct MacBrainApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("MacBrain") {
            MacBrainWorkspaceView(coordinator: appDelegate.coordinator)
                .frame(minWidth: 960, minHeight: 680)
        }
        .defaultSize(width: 1_220, height: 800)

        Settings {
            MacBrainPreferencesView(coordinator: appDelegate.coordinator)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(OverlayWindowPolicy.applicationActivationPolicy)
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }
}
