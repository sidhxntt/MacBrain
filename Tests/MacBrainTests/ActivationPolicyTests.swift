import Foundation
import XCTest

final class ActivationPolicyTests: XCTestCase {
    func testStartupDoesNotForceMacBrainToForeground() throws {
        let appSource = try String(contentsOf: sourceURL("Sources/MacBrain/App/MacBrainApp.swift"))
        let coordinatorSource = try String(contentsOf: sourceURL("Sources/MacBrain/App/AppCoordinator.swift"))

        XCTAssertFalse(appSource.contains("NSApp.activate(ignoringOtherApps: true)"))
        XCTAssertFalse(coordinatorSource.contains("await Task.yield()\n            NSApp.activate(ignoringOtherApps: true)"))
    }

    func testExplicitSidebarInteractionRetainsForegroundActivation() throws {
        let controllerSource = try String(contentsOf: sourceURL("Sources/MacBrain/Services/SidebarPanelController.swift"))

        XCTAssertTrue(controllerSource.contains("private func bringToFrontAndFocus"))
        XCTAssertTrue(controllerSource.contains("NSApp.activate(ignoringOtherApps: true)"))
    }

    func testGrantedPhotoPermissionDoesNotForegroundTheApplicationDuringSync() throws {
        let source = try String(contentsOf: sourceURL("Sources/MacBrain/Services/AppleProductivityConnectors.swift"))
        let function = try XCTUnwrap(source.range(of: "func requestPhotosAccess() async -> PHAuthorizationStatus"))
        let functionEnd = try XCTUnwrap(source.range(of: "private func withForegroundPermissionWindow"))
        let implementation = String(source[function.lowerBound..<functionEnd.lowerBound])
        let permissionGuard = try XCTUnwrap(implementation.range(of: "guard current == .notDetermined else { return current }"))
        let foregroundWrapper = try XCTUnwrap(implementation.range(of: "await withForegroundPermissionWindow"))

        XCTAssertLessThan(permissionGuard.lowerBound, foregroundWrapper.lowerBound)
    }

    private func sourceURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
    }
}
