import SwiftUI

struct LocalExtractionView: View {
    let document: LocalPDFDocument?
    @ObservedObject var coordinator: LocalProcessingCoordinator
    let parse: () -> Void
    let revealPDF: () -> Void
    /// Opens the leading Parsers panel, where engines are chosen and set up.
    let showParsers: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WorkspaceTheme.sectionSpacing) {
            selectedParserSummary

            if document != nil {
                ForEach(coordinator.pageLifecycleGroups) { group in
                    ParserPageLifecycleView(
                        parserName: group.parserName,
                        lifecycles: group.lifecycles
                    )
                }
            }

            if document != nil {
                Divider()
                extractionControls
            } else {
                WorkspaceNoticeView(
                    message: "Open a PDF to enable parsing.",
                    systemImage: "info.circle",
                    color: .secondary
                )
            }

            if coordinator.outputText.isEmpty == false {
                ExtractionOutputView(coordinator: coordinator)
            }
        }
    }

    /// Which engine will run, and one click back to the Parsers panel to change
    /// it. Choosing and installing engines lives there now, so this card stays
    /// about the run.
    private var selectedParserSummary: some View {
        HStack(alignment: .firstTextBaseline, spacing: WorkspaceTheme.standardSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Parser")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(coordinator.selectedDescriptor.name)
                    .font(.headline)
                Text(coordinator.selectedAvailability.message)
                    .font(.caption)
                    .foregroundStyle(
                        coordinator.selectedAvailability.isReady ? WorkspaceTheme.brand : .secondary
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Change", action: showParsers)
                .buttonStyle(.bordered)
                .disabled(coordinator.isRunning || coordinator.isInstalling)
                .accessibilityHint("Opens the Parsers panel")
        }
        .padding(WorkspaceTheme.standardSpacing)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: WorkspaceTheme.cardRadius))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Selected parser \(coordinator.selectedDescriptor.name), \(coordinator.selectedAvailability.message)"
        )
    }

    @ViewBuilder
    private var extractionControls: some View {
        if coordinator.isInstalling {
            parsersHandoff(message: coordinator.setupProgress?.message
                ?? "Setting this parser up. Progress is in Parsers.")
        } else if coordinator.isRunning {
            RunProgressView(coordinator: coordinator)
        } else if coordinator.canResumeLatestRun, let document {
            VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
                Text(coordinator.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    coordinator.resume(document: document)
                } label: {
                    Text(resumeButtonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Continues this run using pages already saved on this Mac")

                Button("Start New Run", action: parse)
                    .buttonStyle(.bordered)
            }
        } else if coordinator.selectedAvailability.isReady {
            VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
                Text(coordinator.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: parse) {
                    Text("Parse with \(coordinator.selectedDescriptor.name)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Extracts on this Mac without uploading the PDF")
            }
        } else {
            parsersHandoff(message: coordinator.statusMessage)
        }
    }

    /// The parser cannot run yet. Say why, then send the reader to the one place
    /// that can fix it.
    private func parsersHandoff(message: String) -> some View {
        VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: showParsers) {
                Text("Open Parsers")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Set this parser up in the Parsers panel")
        }
    }

    private var resumeButtonTitle: String {
        let completed = coordinator.completedPageCount
        let total = coordinator.totalPageCount
        guard completed > 0, total > completed else { return "Resume Run" }
        return "Resume from Page \(completed + 1)"
    }
}
