import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum LocalSourcePicker {
    static func chooseFolder() -> URL? {
        choose(prompt: "Choose a folder to index", allowedTypes: [], directories: true)
    }

    static func chooseGitRepository() -> URL? {
        choose(prompt: "Choose a Git repository", allowedTypes: [], directories: true)
    }

    static func chooseBrowserProfile() -> URL? {
        choose(prompt: "Choose a browser profile folder", allowedTypes: [], directories: true)
    }

    private static func choose(prompt: String, allowedTypes: [String], directories: Bool) -> URL? {
        let panel = NSOpenPanel()
        panel.message = prompt
        panel.prompt = "Choose"
        panel.canChooseFiles = !directories
        panel.canChooseDirectories = directories
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = allowedTypes.compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }
}
