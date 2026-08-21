import Testing
@testable import Okra

@Suite("Assistant command router")
struct AssistantCommandRouterTests {
    @Test("Slash commands route to their destination type")
    func slashCommandsRouteToDestinations() {
        #expect(mountedPlugin("/extract") == .extract)
        #expect(mountedPlugin("/redact") == .redact)
        #expect(mountedActivity("/runs") == .runs)
    }

    @Test("Plain words keep plugins and activity separate")
    func keywordsRouteToDestinations() {
        #expect(mountedPlugin("parse the tables in this filing") == .extract)
        #expect(mountedPlugin("can you OCR this?") == .extract)
        #expect(mountedPlugin("redact the PII before I share it") == .redact)
        #expect(mountedActivity("show my recent runs") == .runs)
    }

    @Test("Extract wins when a request mixes run and parse words")
    func extractOutranksRuns() {
        #expect(mountedPlugin("run a parse on this") == .extract)
    }

    @Test("Open requests trigger the file picker")
    func openRequestsTriggerPicker() {
        let replies = [
            AssistantCommandRouter.reply(to: "/open", documentIsOpen: false),
            AssistantCommandRouter.reply(to: "open another pdf", documentIsOpen: true),
        ]
        for reply in replies {
            guard case .openPDF = reply else {
                Issue.record("Expected .openPDF, got \(reply)")
                continue
            }
        }
    }

    @Test("Help and unmatched input answer with text, never a mount")
    func helpAndFallbackAreText() {
        for input in ["/help", "help", "?", "what is the meaning of life"] {
            let reply = AssistantCommandRouter.reply(to: input, documentIsOpen: true)
            guard case .text = reply else {
                Issue.record("Expected .text for \(input), got \(reply)")
                continue
            }
        }
    }

    @Test("The extract note reflects whether a document is open")
    func extractNoteTracksDocumentState() {
        guard case .plugin(.extract, let openNote) =
            AssistantCommandRouter.reply(to: "/extract", documentIsOpen: true),
            case .plugin(.extract, let closedNote) =
            AssistantCommandRouter.reply(to: "/extract", documentIsOpen: false) else {
            Issue.record("Expected extract mounts for both document states")
            return
        }
        #expect(openNote != closedNote)
    }

    private func mountedPlugin(_ input: String) -> AssistantPlugin? {
        if case .plugin(let plugin, _) = AssistantCommandRouter.reply(
            to: input,
            documentIsOpen: true
        ) {
            return plugin
        }
        return nil
    }

    private func mountedActivity(_ input: String) -> WorkspaceActivity? {
        if case .activity(let activity, _) = AssistantCommandRouter.reply(
            to: input,
            documentIsOpen: true
        ) {
            return activity
        }
        return nil
    }
}

@Suite("Assistant conversation")
@MainActor
struct AssistantConversationTests {
    @Test("Opens with a single welcome entry")
    func opensWithWelcome() {
        let conversation = AssistantConversation()
        #expect(conversation.entries.count == 1)
        #expect(conversation.entries.first?.kind == .assistant(AssistantConversation.welcomeText))
    }

    @Test("Sending appends the user text, a reply, and the plugin card once")
    func sendAppendsUserReplyAndCard() {
        let conversation = AssistantConversation()
        conversation.send("/extract", documentIsOpen: false, openPDF: {})

        let kinds = conversation.entries.map(\.kind)
        #expect(kinds.contains(.user("/extract")))
        #expect(kinds.contains(.plugin(.extract)))
        #expect(conversation.entries.count == 4)
    }

    @Test("Showing the same activity twice reuses the existing card")
    func showActivityIsIdempotent() {
        let conversation = AssistantConversation()
        let first = conversation.show(.runs)
        let second = conversation.show(.runs)

        #expect(first == second)
        #expect(conversation.entries.filter { $0.kind == .activity(.runs) }.count == 1)
    }

    @Test("Blank input is ignored")
    func blankInputIsIgnored() {
        let conversation = AssistantConversation()
        let id = conversation.send("   \n", documentIsOpen: true, openPDF: {})
        #expect(id == nil)
        #expect(conversation.entries.count == 1)
    }
}
