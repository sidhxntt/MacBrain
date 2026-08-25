import Foundation
import XCTest
@testable import MacBrain

final class ReleaseHardeningTests: XCTestCase {
    func testLocalInferenceEndpointAcceptsOnlyLoopbackHTTP() {
        XCTAssertTrue(LocalInferenceEndpoint.isApproved(URL(string: "http://127.0.0.1:11434")!))
        XCTAssertTrue(LocalInferenceEndpoint.isApproved(URL(string: "http://localhost:11434")!))
        XCTAssertFalse(LocalInferenceEndpoint.isApproved(URL(string: "https://api.example.com")!))
        XCTAssertFalse(LocalInferenceEndpoint.isApproved(URL(string: "http://192.168.1.10:11434")!))
        XCTAssertFalse(LocalInferenceEndpoint.isApproved(URL(string: "file:///tmp/ollama")!))
    }

    func testReleaseChecklistReportsMissingPrerequisitesWithoutSecrets() throws {
        let report = ReleaseChecklist.evaluate(
            signingIdentityAvailable: false,
            notaryCredentialsAvailable: false,
            hasHardenedRuntime: true,
            hasPrivacyUsageDescriptions: true
        )

        XCTAssertEqual(report.missing, [.developerIDSigningIdentity, .notaryCredentials])
        XCTAssertFalse(report.description.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(report.description.localizedCaseInsensitiveContains("password"))
    }
}
