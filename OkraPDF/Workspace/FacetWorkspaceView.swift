import Combine
import SwiftUI

enum FacetWorkspaceMode: String, CaseIterable, Identifiable {
    case extraction = "Extracted"
    case redaction = "Redact"

    var id: String { rawValue }
}

/// Permanent document output surface paired with the source PDF.
///
/// Extraction blocks and redaction candidates share coordinator-owned hover
/// and selection state with PDFKit, so the facet and source remain linked
/// without a chat or command-routing layer between them.
struct FacetWorkspaceView: View {
    let document: LocalPDFDocument?
    @ObservedObject var coordinator: LocalProcessingCoordinator
    @Binding var mode: FacetWorkspaceMode
    let parse: () -> Void
    let showPlugin: (WorkspacePlugin) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                Group {
                    switch mode {
                    case .extraction:
                        LocalExtractionView(
                            document: document,
                            coordinator: coordinator,
                            parse: parse,
                            showPlugin: { showPlugin(.extract) }
                        )
                    case .redaction:
                        redactionFacet
                    }
                }
                .padding(WorkspaceTheme.panelPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Facet, source-linked document output")
        .onChange(of: document?.id) { _ in
            mode = .extraction
        }
        .onReceive(coordinator.redaction.$detection) { detection in
            if detection != nil {
                mode = .redaction
            }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: WorkspaceTheme.standardSpacing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Facet")
                        .font(.headline)
                    Text(headerDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Picker("Facet view", selection: $mode) {
                    ForEach(FacetWorkspaceMode.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 178)
            }
            .padding(WorkspaceTheme.panelPadding)

            Divider()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerDetail: String {
        switch mode {
        case .extraction:
            let count = coordinator.pdfBoundingBoxOverlays.count
            if coordinator.structuredOutput != nil {
                return count == 1 ? "1 source-linked block" : "\(count) source-linked blocks"
            }
            return "Structured output linked to source"
        case .redaction:
            return "Presidio review linked to source"
        }
    }

    @ViewBuilder
    private var redactionFacet: some View {
        if coordinator.structuredOutput != nil {
            PresidioRedactionView(
                redaction: coordinator.redaction,
                showPlugin: { showPlugin(.redact) },
                initiallyExpanded: true
            )
        } else {
            VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
                WorkspaceNoticeView(
                    message: document == nil
                        ? "Open and parse a PDF before detecting PII."
                        : "Parse first with a positioned provider. Redaction reviews source-linked extraction blocks.",
                    systemImage: "viewfinder.circle",
                    color: .secondary
                )

                Button("Show Extracted Facet") {
                    mode = .extraction
                }
                .buttonStyle(.borderedProminent)

                Button("Redact Plugin Settings") {
                    showPlugin(.redact)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
