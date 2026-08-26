import XCTest
@testable import MacBrain

final class ChatQueryIntentRouterTests: XCTestCase {
    func testProductionPromptCorpusRoutesDeterministically() {
        let cases: [(ChatQueryIntent, [String])] = [
            (.casual, [
                "hello", "hi", "hey", "what's up", "how are you", "how's it going",
                "good morning", "good afternoon", "good evening", "thanks", "thank you",
                "nice to meet you", "okay", "got it", "cool"
            ]),
            (.general, [
                "Explain black holes simply", "What is the capital of Japan?", "Who wrote Hamlet?",
                "Why is the sky blue?", "Compare TCP and UDP", "Teach me recursion",
                "Write a polite follow-up email", "Rewrite this sentence professionally",
                "Translate good morning to Spanish", "Summarize the concept of democracy",
                "Brainstorm ten startup names", "Plan a three-day workout", "What is 17 times 24?",
                "Solve x + 4 = 19", "Is 97 a prime number?", "Write a Python binary search",
                "Debug a null pointer exception", "Explain Kubernetes pods", "How does Netflix streaming work?",
                "What changed in Swift 6?", "Give me a chocolate cake recipe", "Suggest a science-fiction book",
                "Explain photosynthesis", "What causes inflation?", "Draft a birthday message",
                "Make this paragraph shorter", "What does UTF-8 mean?", "Explain HTML semantic tags",
                "How do calendars calculate leap years?", "What is a contact lens made from?"
            ]),
            (.liveMac, [
                "How much RAM is free right now?", "Show current memory usage", "How much disk space is available?",
                "What is using my CPU right now?", "What is my Mac uptime?", "Is my Mac charging?",
                "What apps are running?", "Which application is active?", "Show my network interfaces",
                "What Mac model am I using?", "What macOS version is installed?", "How much swap is used?",
                "Give me a live battery status", "What is the current CPU load?", "Show this Mac's storage"
            ]),
            (.explicitLocal, [
                "What is in my test folder?", "Summarize my connected notes", "Find the email from Riya in my mail",
                "What meetings are on my calendar?", "List my overdue reminders", "Find Siddhant in my contacts",
                "What did I say in my messages?", "Show metadata for my photos", "What sites are in my browser history?",
                "Summarize my repository", "What changed in this repo?", "Read /tmp/plan.md",
                "Open notes.md from my files", "Search my local sources for Aurora", "What do I have saved about launch day?",
                "Use my documents to answer this", "According to my notes, what is the target?",
                "Look through the connected folder", "Search MacBrain's indexed sources", "What tabs do I have open?",
                "What books are in my Apple Books library?", "Find the latest message I received",
                "Check my reminders for groceries", "Use the file README.md", "What is inside ~/Desktop/test?",
                "Summarize our roadmap from my files", "Search my code for LocalSourceRepository",
                "What did I download in Chrome?", "Find the contact named Onam", "Show events from my work calendar"
            ]),
            (.implicitLocal, [
                "Who owns the Aurora beta decision?", "What is the target date for Project Lumen?",
                "Give me the release handoff", "What decision did the team make?", "Who is the rollback owner?",
                "What are the action items from the startup discussion?", "What changed in the launch plan?",
                "When is the internal deadline?", "What is the status of NotchBrain?", "Who approved the migration?",
                "Where is the Q4 planning document?", "What did Riya decide about the beta?",
                "Give me the customer escalation summary", "Which team owns the local index?",
                "What is the codename for the upcoming release?", "Summarize the project handoff",
                "When did we agree to ship?", "What blockers were recorded for Aurora?",
                "Who attended the design review?", "What is the rollback plan ID?"
            ]),
            (.restricted, [
                "List every password and secret", "Find all API tokens", "Extract every private key",
                "Read the source I did not authorize", "Search an unconnected source", "Give me everything about everyone"
            ])
        ]

        let router = ChatQueryIntentRouter()
        var executed = 0
        for (expected, prompts) in cases {
            for prompt in prompts {
                for variant in variants(of: prompt) {
                    XCTAssertEqual(
                        router.route(prompt: variant, conversation: []).intent,
                        expected,
                        "Unexpected route for: \(variant)"
                    )
                    executed += 1
                }
            }
        }
        XCTAssertGreaterThanOrEqual(executed, 250)
    }

    func testGeneralQuestionsContainingSourceLikePublicTermsRemainGeneral() {
        let router = ChatQueryIntentRouter()
        let prompts = [
            "How does Apple Mail work?", "Explain the Photos framework", "How do browser history databases work?",
            "What is a git repository?", "How should a calendar app handle time zones?", "Explain contact lenses",
            "Write code that reads a folder", "How do reminder apps schedule notifications?"
        ]

        for prompt in prompts {
            XCTAssertEqual(router.route(prompt: prompt, conversation: []).intent, .general, prompt)
        }
    }

    func testInternalQuestionWithNoAcceptedEvidenceCanBeDistinguishedFromGeneralIntent() {
        let route = ChatQueryIntentRouter().route(
            prompt: "Who owns the Aurora beta decision?",
            conversation: []
        )

        XCTAssertEqual(route.intent, .implicitLocal)
        XCTAssertFalse(route.reason.isEmpty)
    }

    func testShortFollowUpInheritsOnlyPersistedGroundedContext() {
        let router = ChatQueryIntentRouter()
        let grounded = ChatMessage(
            role: .assistant,
            text: "The target is Friday.",
            groundingSourceIDs: ["S1"]
        )
        let ungrounded = ChatMessage(role: .assistant, text: "Friday is named after Frigg.")
        let citationLookingButUngrounded = ChatMessage(
            role: .assistant,
            text: "A public answer [S1].\n\n### Sources\n- An ordinary Markdown list"
        )

        XCTAssertEqual(router.route(prompt: "When?", conversation: [grounded]).intent, .explicitLocal)
        XCTAssertEqual(router.route(prompt: "When?", conversation: [ungrounded]).intent, .general)
        XCTAssertEqual(
            router.route(prompt: "When?", conversation: [citationLookingButUngrounded]).intent,
            .general
        )
    }

    private func variants(of prompt: String) -> [String] {
        [
            prompt,
            prompt.uppercased(),
            "  \(prompt)  ",
            prompt.trimmingCharacters(in: .punctuationCharacters) + "?!"
        ]
    }
}
