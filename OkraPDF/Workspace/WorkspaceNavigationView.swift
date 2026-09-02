import SwiftUI

/// A focused history drawer. Provider and detector configuration live in the
/// app's Settings window, so this panel contains activity only.
struct RunHistoryPanelView: View {
    @ObservedObject var coordinator: LocalProcessingCoordinator
    let openRun: (LocalProcessingRun) -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
                    Text("Runs are stored locally with their output and page checkpoints.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if coordinator.recentRuns.isEmpty {
                        WorkspaceNoticeView(
                            message: "Completed parses appear here.",
                            systemImage: "clock",
                            color: .secondary
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(coordinator.recentRuns) { run in
                                if run.id != coordinator.recentRuns.first?.id { Divider() }
                                Button {
                                    openRun(run)
                                } label: {
                                    RunHistoryRowView(run: run)
                                        .padding(.vertical, WorkspaceTheme.compactSpacing)
                                }
                                .buttonStyle(.plain)
                                .disabled(coordinator.isRunning || coordinator.isInstalling)
                            }
                        }
                    }

                    Divider()

                    Button("Show Runs Folder", action: coordinator.revealRunsFolder)
                        .buttonStyle(.bordered)
                }
                .padding(WorkspaceTheme.panelPadding)
            }
            .workspacePanelTextRendering()
        }
        .background(.bar)
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Runs")
                        .font(.headline)
                    Text("On this Mac")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Hide run history", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .help("Hide run history")
            }
            .padding(WorkspaceTheme.panelPadding)

            Divider()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
