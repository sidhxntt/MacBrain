import Foundation

struct BrowserTabSnapshot: Equatable, Sendable {
    let title: String
    let url: String
}

protocol BrowserTabSnapshotProviding: Sendable {
    func snapshots(for browser: BrowserKind) async -> [BrowserTabSnapshot]
}

struct BrowserTabSnapshotProvider: BrowserTabSnapshotProviding {
    let scriptExecutor: any AppleScriptExecuting

    init(scriptExecutor: any AppleScriptExecuting = AppleScriptExecutor()) {
        self.scriptExecutor = scriptExecutor
    }

    func snapshots(for browser: BrowserKind) async -> [BrowserTabSnapshot] {
        guard let output = try? await scriptExecutor.execute(script(for: browser)) else { return [] }
        return output.split(separator: "\u{1E}").compactMap { row in
            let fields = row.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 2, !fields[0].isEmpty else { return nil }
            return BrowserTabSnapshot(title: fields[1].isEmpty ? fields[0] : fields[1], url: fields[0])
        }
    }

    private func script(for browser: BrowserKind) -> String {
        if browser == .safari {
            return """
            tell application "Safari"
                set outputRows to {}
                repeat with browserWindow in every window
                    repeat with browserTab in every tab of browserWindow
                        set end of outputRows to (URL of browserTab as text) & character id 31 & (name of browserTab as text)
                    end repeat
                end repeat
                set AppleScript's text item delimiters to character id 30
                return outputRows as text
            end tell
            """
        }
        return """
        tell application "\(browser.applicationName)"
            set outputRows to {}
            repeat with browserWindow in every window
                repeat with browserTab in every tab of browserWindow
                    set end of outputRows to (URL of browserTab as text) & character id 31 & (title of browserTab as text)
                end repeat
            end repeat
            set AppleScript's text item delimiters to character id 30
            return outputRows as text
        end tell
        """
    }
}
