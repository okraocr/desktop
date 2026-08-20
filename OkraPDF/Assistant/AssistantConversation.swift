import Foundation

struct AssistantEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case user(String)
        case assistant(String)
        case plugin(AssistantPlugin)
    }

    let id: Int
    let kind: Kind
}

/// Session-scoped timeline for the assistant panel.
///
/// Entries are user text, assistant text, or a mounted plugin card. A plugin
/// mounts at most once — repeating a request scrolls back to the existing
/// card instead of duplicating live coordinator UI.
@MainActor
final class AssistantConversation: ObservableObject {
    @Published private(set) var entries: [AssistantEntry] = []
    private var nextEntryID = 0

    init() {
        append(.assistant(Self.welcomeText))
    }

    /// Routes composer input and returns the entry to scroll to.
    @discardableResult
    func send(
        _ text: String,
        documentIsOpen: Bool,
        openPDF: () -> Void
    ) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        append(.user(trimmed))

        switch AssistantCommandRouter.reply(to: trimmed, documentIsOpen: documentIsOpen) {
        case .text(let reply):
            return append(.assistant(reply))
        case .plugin(let plugin, let note):
            append(.assistant(note))
            return mount(plugin)
        case .openPDF(let note):
            let id = append(.assistant(note))
            openPDF()
            return id
        }
    }

    /// Mounts a plugin card, or returns the existing card's entry.
    @discardableResult
    func mount(_ plugin: AssistantPlugin) -> Int {
        if let existing = entries.last(where: { $0.kind == .plugin(plugin) }) {
            return existing.id
        }
        return append(.plugin(plugin))
    }

    @discardableResult
    private func append(_ kind: AssistantEntry.Kind) -> Int {
        let id = nextEntryID
        nextEntryID += 1
        entries.append(AssistantEntry(id: id, kind: kind))
        return id
    }

    static let welcomeText = """
        Read the PDF in the main window; this panel runs local plugins — \
        Extract, Redact, and Runs. Ask in plain words or type /help. \
        Nothing leaves this Mac.
        """
}
