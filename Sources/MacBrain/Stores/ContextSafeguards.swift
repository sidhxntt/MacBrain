import AppKit
import ApplicationServices
import Combine
import Foundation

@MainActor
final class ContextSafeguards: ObservableObject {
    @Published private(set) var visibleChips: [ContextAttachment] = []
    @Published private(set) var recoveryGuidance: String?

    func enable(_ kind: ContextAttachmentKind, value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            recoveryGuidance = "No \(kind.title.lowercased()) is available. Select content or grant the requested permission, then try again."
            return
        }
        visibleChips.removeAll { $0.kind == kind }
        visibleChips.append(ContextAttachment(kind: kind, value: trimmed))
        recoveryGuidance = nil
    }

    func captureClipboard() { enable(.clipboard, value: NSPasteboard.general.string(forType: .string) ?? "") }

    func captureSelectedText() {
        guard AXIsProcessTrusted() else {
            recoveryGuidance = "Allow Accessibility access in System Settings → Privacy & Security → Accessibility to include selected text."
            return
        }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused
        else {
            recoveryGuidance = "MacBrain could not read the focused selection. Select text in an accessible app, then try again."
            return
        }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let value = selected as? String
        else {
            recoveryGuidance = "No selected text is available from the focused app."
            return
        }
        enable(.selectedText, value: value)
    }

    func captureActiveApplication() {
        let application = NSWorkspace.shared.frontmostApplication
        enable(.activeWindow, value: [application?.localizedName, application?.bundleIdentifier].compactMap { $0 }.joined(separator: " — "))
    }

    func captureRepository() {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent(".git").path) {
                let branch = Self.gitOutput(["-C", directory.path, "branch", "--show-current"])
                enable(.repository, value: "\(directory.lastPathComponent)\(branch.map { " (\($0))" } ?? "")")
                return
            }
            directory.deleteLastPathComponent()
        }
        recoveryGuidance = "No Git repository was detected from MacBrain’s current folder."
    }

    func remove(_ kind: ContextAttachmentKind) { visibleChips.removeAll { $0.kind == kind } }

    func consumeOneTurnAttachments() { visibleChips.removeAll { $0.kind.expiresAfterRequest } }

    var promptContext: String { promptContext(for: "") }

    func promptContext(for prompt: String) -> String {
        let relevant = visibleChips.filter { attachment in
            attachment.kind != .repository || Self.isRepositoryRelevant(to: prompt)
        }
        return PromptBudgetPolicy().boundedContext(relevant)
    }

    private static func isRepositoryRelevant(to prompt: String) -> Bool {
        let query = prompt.lowercased()
        return ["repo", "repository", "branch", "commit", "git", "code", "changed", "diff"].contains { query.contains($0) }
    }

    private static func gitOutput(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch { return nil }
    }
}
