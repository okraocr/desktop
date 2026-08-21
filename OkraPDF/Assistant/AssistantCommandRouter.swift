import Foundation

enum AssistantReply: Equatable {
    case text(String)
    case plugin(AssistantPlugin, note: String)
    case activity(WorkspaceActivity, note: String)
    case openPDF(note: String)
}

/// Deterministic, on-device routing from composer input to a reply.
///
/// This is intentionally not a language model: slash commands match exactly,
/// plain text matches on word tokens, and anything unmatched gets the help
/// text. Keeping the router pure keeps it testable and keeps the assistant
/// honest about what it is.
enum AssistantCommandRouter {
    static func reply(to input: String, documentIsOpen: Bool) -> AssistantReply {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()

        switch lowered {
        case "/help", "help", "?":
            return .text(helpText)
        case AssistantPlugin.extract.command:
            return extractReply(documentIsOpen: documentIsOpen)
        case AssistantPlugin.redact.command:
            return redactReply(documentIsOpen: documentIsOpen)
        case WorkspaceActivity.runs.command:
            return .activity(.runs, note: "Runs completed on this Mac, newest first.")
        case "/open":
            return .openPDF(note: "Opening the file picker.")
        default:
            break
        }

        let tokens = Set(
            lowered
                .split(whereSeparator: { $0.isLetter == false })
                .map(String.init)
        )

        if tokens.isDisjoint(with: extractKeywords) == false {
            return extractReply(documentIsOpen: documentIsOpen)
        }
        if tokens.isDisjoint(with: redactKeywords) == false {
            return redactReply(documentIsOpen: documentIsOpen)
        }
        if tokens.isDisjoint(with: runsKeywords) == false {
            return .activity(.runs, note: "Runs completed on this Mac, newest first.")
        }
        if tokens.isDisjoint(with: openKeywords) == false {
            return .openPDF(note: "Opening the file picker.")
        }

        return .text(fallbackText)
    }

    static let helpText = """
        This panel routes requests to local tools and activity. There is no cloud model \
        behind it and nothing leaves this Mac.

        Open the left navigation for Plugins and Runs. Plugin setup and installation progress stay under Plugins; run history stays under Activity.

        /extract — parse the open PDF with a local provider
        /redact — detect PII after a parse and export burned-in boxes
        /runs — recent local runs and outputs
        /open — choose a PDF
        """

    static let fallbackText = """
        I match simple requests to local tools — try “parse this”, \
        “redact PII”, or “show runs”. Type /help for every command.
        """

    private static func extractReply(documentIsOpen: Bool) -> AssistantReply {
        .plugin(
            .extract,
            note: documentIsOpen
                ? "Extract is ready. Pick a provider, then click Parse — nothing runs before that."
                : "Extract is mounted. Open or drop a PDF to enable Parse."
        )
    }

    private static func redactReply(documentIsOpen: Bool) -> AssistantReply {
        .plugin(
            .redact,
            note: documentIsOpen
                ? "Redact reviews positioned blocks from a completed parse. Detection starts only when you ask."
                : "Redact is mounted. Open a PDF and parse it first — detection needs positioned blocks."
        )
    }

    private static let extractKeywords: Set<String> = [
        "extract", "extraction", "parse", "parsing", "parser",
        "ocr", "markdown", "table", "tables",
    ]

    private static let redactKeywords: Set<String> = [
        "redact", "redaction", "pii", "presidio", "anonymize", "anonymise",
    ]

    private static let runsKeywords: Set<String> = [
        "run", "runs", "history", "output", "outputs", "results", "previous",
    ]

    private static let openKeywords: Set<String> = [
        "open", "load", "import", "file", "pdf", "document", "drop",
    ]
}
