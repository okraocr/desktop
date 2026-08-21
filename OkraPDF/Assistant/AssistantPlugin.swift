/// A local feature that mounts into the assistant panel as a card.
///
/// The reader stays permanent in the center. Features mount on demand in the
/// trailing Assistant, while their status and dependency setup live in the
/// Plugins section of the leading navigation. Nothing here talks to the network.
enum AssistantPlugin: String, CaseIterable, Identifiable {
    case extract
    case redact

    var id: String { rawValue }

    var name: String {
        switch self {
        case .extract:
            return "Extract"
        case .redact:
            return "Redact"
        }
    }

    var systemImage: String {
        switch self {
        case .extract:
            return "text.viewfinder"
        case .redact:
            return "eye.slash"
        }
    }

    var summary: String {
        switch self {
        case .extract:
            return "Parse the open PDF with a local provider"
        case .redact:
            return "Review PII candidates, export burned-in boxes"
        }
    }

    var command: String {
        "/\(rawValue)"
    }
}
