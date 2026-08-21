import Foundation

struct AssistantEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case user(String)
        case assistant(String)
        case plugin(AssistantPlugin)
        case activity(WorkspaceActivity)
    }

    let id: Int
    let kind: Kind
}

/// Session-scoped timeline for the assistant panel.
///
/// Entries are user text, assistant text, a mounted plugin card, or workspace
/// activity. Each destination appears at most once so repeating a request
/// scrolls back to the existing live coordinator UI.
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
        case .activity(let activity, let note):
            append(.assistant(note))
            return show(activity)
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

    /// Shows an activity card, or returns the existing card's entry.
    @discardableResult
    func show(_ activity: WorkspaceActivity) -> Int {
        if let existing = entries.last(where: { $0.kind == .activity(activity) }) {
            return existing.id
        }
        return append(.activity(activity))
    }

    @discardableResult
    private func append(_ kind: AssistantEntry.Kind) -> Int {
        let id = nextEntryID
        nextEntryID += 1
        entries.append(AssistantEntry(id: id, kind: kind))
        return id
    }

    static let welcomeText = """
        Read the PDF in the main window; this panel routes to local tools. \
        Extract and Redact are plugins; Runs is local activity. Ask in plain words or type /help. \
        Nothing leaves this Mac.
        """
}
