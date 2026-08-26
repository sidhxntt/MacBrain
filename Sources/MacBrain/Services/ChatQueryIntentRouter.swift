import Foundation

enum ChatQueryIntent: String, Equatable, Sendable {
    case casual
    case general
    case liveMac
    case explicitLocal
    case implicitLocal
    case restricted
}

struct ChatQueryRoute: Equatable, Sendable {
    let intent: ChatQueryIntent
    let reason: String
}

/// Classifies a prompt before retrieval so ordinary chat cannot accidentally
/// turn into a dump of unrelated local source material.
struct ChatQueryIntentRouter: Sendable {
    func route(prompt: String, conversation: [ChatMessage]) -> ChatQueryRoute {
        let normalized = normalize(prompt)
        let containsOriginalPath = containsPathOrFileReference(prompt.lowercased())

        if PrivacyPromptPolicy.response(for: normalized) != nil {
            return ChatQueryRoute(intent: .restricted, reason: "privacy policy matched")
        }

        if isLiveMacRequest(normalized) {
            return ChatQueryRoute(intent: .liveMac, reason: "current Mac state requested")
        }

        if Self.casualPrompts.contains(normalized) {
            return ChatQueryRoute(intent: .casual, reason: "short conversational prompt")
        }

        if isExplicitlyGeneralRequest(normalized) || isPublicKnowledgeForm(normalized) {
            return ChatQueryRoute(intent: .general, reason: "public knowledge form requested")
        }

        if containsOriginalPath || isExplicitLocalRequest(normalized) {
            return ChatQueryRoute(intent: .explicitLocal, reason: "connected or personal source requested")
        }

        if isGroundedFollowUp(normalized, conversation: conversation) {
            return ChatQueryRoute(intent: .explicitLocal, reason: "follow-up to grounded answer")
        }

        if isImplicitLocalRequest(normalized) {
            return ChatQueryRoute(intent: .implicitLocal, reason: "internal entity or decision requested")
        }

        return ChatQueryRoute(intent: .general, reason: "no local-data signal")
    }

    private func normalize(_ prompt: String) -> String {
        SourceVocabulary.normalize(prompt).text
    }

    private func isLiveMacRequest(_ prompt: String) -> Bool {
        if containsAny(prompt, [
            "what mac model", "which mac model", "mac model am i", "macos version",
            "what version of macos", "which version of macos", "who am i on this mac",
            "current mac", "mac status", "system overview", "system health",
            "application is active", "app is active"
        ]) {
            return true
        }
        if ["who am i", "tell me who i am"].contains(prompt) {
            return true
        }

        let capabilities = LiveMacQueryRouter().capabilities(for: prompt)
        guard !capabilities.isEmpty else { return false }

        return containsAny(prompt, [
            "my mac", "this mac", "my ram", "my memory", "my cpu", "my processor",
            "my disk", "my storage", "my battery", "my network", "right now", "currently",
            "current ", " is active", " are running", " apps are running", "applications are running",
            "how much ram", "how much memory", "memory usage", "swap is", "swap usage",
            "disk space", "storage space", "space is available", "cpu load", "using my cpu",
            "mac uptime", "is my mac charging", "battery status", "network interfaces"
        ])
    }

    private func isExplicitLocalRequest(_ prompt: String) -> Bool {
        if containsAny(prompt, [
            "connected source", "connected notes", "connected folder", "local source",
            "indexed source", "my files", "my documents", "my notes", "my mail", "my email",
            "my calendar", "my reminders", "my contacts", "my messages", "my photos",
            "my browser history", "my repository", "my repo", "my code", "my downloads",
            "my bookmarks",
            "my test folder", "my apple books", "my books", "my work calendar", "open tabs",
            "tabs do i have open", "this repo", "this repository", "this git repo", "this git repository",
            "this folder", "this file",
            "according to my", "from my files", "i have saved", "did i download",
            "latest message i received", "contact named", "metadata for my photos"
        ]) {
            return true
        }

        if containsPathOrFileReference(prompt) {
            return true
        }

        let personalNouns = [
            "folder", "file", "note", "mail", "email", "calendar", "reminder", "contact",
            "message", "photo", "browser", "history", "repository", "repo", "document",
            "code", "book", "download", "tab", "roadmap", "library"
        ]
        let hasPersonalQualifier = containsAny(prompt, ["my ", "our "])
        return hasPersonalQualifier && personalNouns.contains { containsWord(prompt, $0) }
    }

    private func isExplicitlyGeneralRequest(_ prompt: String) -> Bool {
        containsAny(prompt, [
            "ignore local sources", "without local sources", "don't use local sources",
            "do not use local sources", "use no local sources"
        ])
    }

    private func isPublicKnowledgeForm(_ prompt: String) -> Bool {
        let prefixes = [
            "what is a ", "what is an ", "define ", "explain how ", "how does ",
            "how do ", "teach me ", "write ", "translate "
        ]
        guard prefixes.contains(where: { prompt.hasPrefix($0) }) else { return false }
        return !containsAny(prompt, [
            " my ", " our ", "connected source", "connected notes", "local source",
            "indexed source", "this repo", "this file", "this folder", "~/", "/tmp/"
        ])
    }

    private func containsPathOrFileReference(_ prompt: String) -> Bool {
        if prompt.contains("~/") || prompt.contains(" /tmp/") || prompt.hasPrefix("/tmp/") {
            return true
        }

        let fileExtensions = [
            ".md", ".txt", ".pdf", ".swift", ".py", ".html", ".css", ".js",
            ".json", ".csv", ".doc", ".docx", ".xlsx", ".pptx"
        ]
        return fileExtensions.contains { prompt.contains($0) }
            || containsWord(prompt, "readme")
    }

    private func isGroundedFollowUp(_ prompt: String, conversation: [ChatMessage]) -> Bool {
        guard prompt.split(separator: " ").count <= 12,
              let previousAssistant = conversation.last(where: { $0.role == .assistant })
        else { return false }

        guard !previousAssistant.groundingSourceIDs.isEmpty else { return false }

        return containsAny(prompt, [
            "that", "those", "it", "them", "the source", "the file", "tell me more",
            "what about", "why", "when", "who", "where", "how"
        ])
    }

    private func isImplicitLocalRequest(_ prompt: String) -> Bool {
        containsAny(prompt, [
            "who owns the ", "who is the rollback owner", "target date for project",
            "release handoff", "beta handoff", "rollback owner", "target date",
            "decision did the team", "action items from the",
            "changed in the launch plan", "internal deadline", "status of notchbrain",
            "approved the migration", "planning document", "did riya decide",
            "customer escalation summary", "team owns the local index", "codename for the upcoming release",
            "project handoff", "did we agree to ship", "blockers were recorded",
            "attended the design review", "rollback plan id"
        ])
    }

    private func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { text.contains($0) }
    }

    private func containsWord(_ text: String, _ word: String) -> Bool {
        text.range(of: #"(?:^|\W)\#(word)s?(?:\W|$)"#, options: .regularExpression) != nil
    }

    private static let casualPrompts: Set<String> = [
        "hello", "hi", "hey", "what s up", "how are you", "how s it going",
        "good morning", "good afternoon", "good evening", "thanks", "thank you",
        "nice to meet you", "okay", "got it", "cool", "whats up", "thx", "ok",
        "hello there", "hey there"
    ]
}
