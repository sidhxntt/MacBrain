@testable import MacBrain
import Foundation
import XCTest

final class BrowserProfileCatalogTests: XCTestCase {
    func testCatalogIncludesEverySupportedBrowserDefinition() {
        let identifiers = Set(BrowserProfileCatalog.defaultDefinitions.map(\.id))

        XCTAssertEqual(
            identifiers,
            [
                "safari", "chrome", "chrome-canary", "chromium", "brave", "brave-beta", "brave-nightly",
                "opera", "opera-gx", "firefox", "firefox-developer-edition", "firefox-nightly", "arc", "dia",
                "vivaldi", "edge", "edge-beta", "edge-dev", "edge-canary", "orion", "duckduckgo", "tor-browser"
            ]
        )
    }

    func testDiscoveryFindsChromiumProfilesAndFirefoxProfilesFromInjectedHomeDirectory() throws {
        let homeURL = URL(fileURLWithPath: "/fixture-home", isDirectory: true)
        let fileSystem = FixtureBrowserProfileFileSystem(
            directories: [
                "Library/Application Support/Google/Chrome/Default",
                "Library/Application Support/Google/Chrome/Profile 2",
                "Library/Application Support/Google/Chrome/Guest Profile",
                "Library/Application Support/Firefox/Profiles/ab12.default-release",
                "Library/Application Support/Firefox/Profiles/dev-edition-default"
            ]
        )
        let catalog = BrowserProfileCatalog(homeURL: homeURL, fileSystem: fileSystem)

        let profiles = try catalog.detectedProfiles()

        XCTAssertEqual(
            profiles.map(\.browserIdentifier),
            ["chrome", "chrome", "chrome", "firefox", "firefox"]
        )
        XCTAssertEqual(
            profiles.map(\.profileDisplayName),
            ["Default", "Profile 2", "Guest Profile", "ab12.default-release", "dev-edition-default"]
        )
        XCTAssertEqual(profiles[0].engine, .chromium)
        XCTAssertEqual(profiles[3].engine, .firefox)
        XCTAssertTrue(profiles[0].appBundleIdentifiers.contains("com.google.Chrome"))
        XCTAssertTrue(profiles[0].candidateApplicationPaths.contains("/Applications/Google Chrome.app"))
    }

    func testDiscoveryReturnsSafariLibraryRootAsSingleProfile() throws {
        let homeURL = URL(fileURLWithPath: "/fixture-home", isDirectory: true)
        let catalog = BrowserProfileCatalog(
            homeURL: homeURL,
            fileSystem: FixtureBrowserProfileFileSystem(directories: ["Library/Safari"])
        )

        let profiles = try catalog.detectedProfiles()

        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].browserIdentifier, "safari")
        XCTAssertEqual(profiles[0].browserDisplayName, "Safari")
        XCTAssertEqual(profiles[0].engine, .safari)
        XCTAssertEqual(profiles[0].profileDisplayName, "Safari")
        XCTAssertEqual(profiles[0].profileURL.path, "/fixture-home/Library/Safari")
    }

    func testCatalogDiscoversDiaChromiumProfilesFromItsVerifiedLocalRoot() throws {
        let definition = try XCTUnwrap(
            BrowserProfileCatalog.defaultDefinitions.first(where: { $0.id == "dia" })
        )

        XCTAssertEqual(definition.engine, .chromium)
        XCTAssertEqual(definition.profileRootRelativePaths, ["Library/Application Support/Dia/User Data"])
        XCTAssertTrue(definition.canDiscoverProfiles)
    }

    func testDiscoveryRecognizesUnknownChromiumProfileFromStorageSignature() throws {
        let homeURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let profileURL = homeURL
            .appendingPathComponent("Library/Application Support/Example Browser/User Data/Default", isDirectory: true)
        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
        try Data().write(to: profileURL.appendingPathComponent("History"))

        let profiles = try BrowserProfileCatalog(homeURL: homeURL).detectedProfiles()

        let expectedPath = profileURL.resolvingSymlinksInPath().path
        let profile = try XCTUnwrap(profiles.first { $0.profileURL.resolvingSymlinksInPath().path == expectedPath })
        XCTAssertEqual(profile.browserIdentifier, "generic-chromium")
        XCTAssertEqual(profile.browserDisplayName, "Example Browser")
        XCTAssertEqual(profile.profileDisplayName, "Default")
    }
}

private struct FixtureBrowserProfileFileSystem: BrowserProfileFileSystem {
    let directories: Set<String>

    init(directories: [String]) {
        self.directories = Set(directories)
    }

    func directoryExists(at url: URL) -> Bool {
        directories.contains(url.path.replacingOccurrences(of: "/fixture-home/", with: ""))
    }

    func fileExists(at url: URL) -> Bool {
        false
    }

    func directoryContents(at url: URL) throws -> [URL] {
        let relativePath = url.path.replacingOccurrences(of: "/fixture-home/", with: "")
        let prefix = relativePath.isEmpty ? "" : relativePath + "/"
        let names = Set(directories.compactMap { path -> String? in
            guard path.hasPrefix(prefix) else { return nil }
            let suffix = String(path.dropFirst(prefix.count))
            guard suffix.isEmpty == false, suffix.contains("/") == false else { return nil }
            return suffix
        })
        return names.sorted().map { url.appendingPathComponent($0, isDirectory: true) }
    }
}
