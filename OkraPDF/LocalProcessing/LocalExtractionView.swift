import SwiftUI

struct LocalExtractionView: View {
    let document: LocalPDFDocument?
    @ObservedObject var coordinator: LocalProcessingCoordinator
    let parse: () -> Void
    let revealPDF: () -> Void
    /// Opens the sidebar, where parsers are chosen and set up.
    let showPlugins: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WorkspaceTheme.sectionSpacing) {
            selectedPluginSummary

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

            if coordinator.structuredOutput != nil {
                PresidioRedactionView(
                    coordinator: coordinator,
                    redaction: coordinator.redaction
                )
            }
        }
    }

    /// Which engine will run, and one click back to the Plugins list to change
    /// it. Choosing and installing parsers lives in the sidebar now, so this
    /// panel stays about the run.
    private var selectedPluginSummary: some View {
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

            Button("Change", action: showPlugins)
                .buttonStyle(.bordered)
                .disabled(coordinator.isRunning || coordinator.isInstalling)
                .accessibilityHint("Opens the Plugins list in the workspace sidebar")
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
            pluginsHandoff(message: coordinator.setupProgress?.message
                ?? "Setting this parser up. Progress is in Plugins.")
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
            pluginsHandoff(message: coordinator.statusMessage)
        }
    }

    /// The parser cannot run yet. Say why, then send the reader to the one place
    /// that can fix it.
    private func pluginsHandoff(message: String) -> some View {
        VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: showPlugins) {
                Text("Open Plugins")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Set this parser up in the workspace sidebar")
        }
    }

    private var resumeButtonTitle: String {
        let completed = coordinator.completedPageCount
        let total = coordinator.totalPageCount
        guard completed > 0, total > completed else { return "Resume Run" }
        return "Resume from Page \(completed + 1)"
    }
}
