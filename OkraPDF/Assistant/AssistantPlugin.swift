/// A local feature that mounts into the assistant panel as a card.
///
/// Plugins are the only way features surface in the shell: the reader stays
/// permanent in the center and everything else arrives on demand in the
/// trailing panel. Nothing here talks to the network.
enum AssistantPlugin: String, CaseIterable, Identifiable {
    case extract
    case redact
    case runs

    var id: String { rawValue }

    var name: String {
        switch self {
        case .extract:
            return "Extract"
        case .redact:
            return "Redact"
        case .runs:
            return "Runs"
        }
    }

    var systemImage: String {
        switch self {
        case .extract:
            return "text.viewfinder"
        case .redact:
            return "eye.slash"
        case .runs:
            return "clock.arrow.circlepath"
        }
    }

    var summary: String {
        switch self {
        case .extract:
            return "Parse the open PDF with a local provider"
        case .redact:
            return "Review PII candidates, export burned-in boxes"
        case .runs:
            return "Recent local runs on this Mac"
        }
    }

    var command: String {
        "/\(rawValue)"
    }
}
