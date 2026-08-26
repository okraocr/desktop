/// A local capability configured from workspace navigation.
///
/// Plugins own dependency and provider setup. Their document-facing results
/// live in the permanent Facet surface beside the source PDF.
enum WorkspacePlugin: String, CaseIterable, Identifiable {
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
            return "Review PII candidates and export burned-in boxes"
        }
    }
}
