import SwiftUI

struct ExtractionInspectorView: View {
    let document: LocalPDFDocument?
    let importError: String?
    @ObservedObject var coordinator: LocalProcessingCoordinator
    let parse: () -> Void
    let revealPDF: () -> Void
    let showPlugins: () -> Void
    let dismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WorkspaceTheme.sectionSpacing) {
                HStack(alignment: .top, spacing: WorkspaceTheme.standardSpacing) {
                    VStack(alignment: .leading, spacing: WorkspaceTheme.compactSpacing) {
                        Text("Extract")
                            .font(.title2)
                            .bold()
                        Text("Runs on this Mac. Nothing starts until you click Parse.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button("Hide Extract", systemImage: "xmark", action: dismiss)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .help("Hide Extract")
                }

                if let importError {
                    WorkspaceNoticeView(
                        message: importError,
                        systemImage: "exclamationmark.triangle.fill",
                        color: .red
                    )
                }

                LocalExtractionView(
                    document: document,
                    coordinator: coordinator,
                    parse: parse,
                    revealPDF: revealPDF,
                    showPlugins: showPlugins
                )
            }
            .padding(WorkspaceTheme.panelPadding)
        }
        .background(.background)
    }
}
