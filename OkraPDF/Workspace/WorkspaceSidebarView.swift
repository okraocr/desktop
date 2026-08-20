import SwiftUI

struct WorkspaceSidebarView: View {
    let document: LocalPDFDocument?
    @ObservedObject var coordinator: LocalProcessingCoordinator
    let openRun: (LocalProcessingRun) -> Void
    let dismiss: () -> Void

    var body: some View {
        List {
            Section("Document") {
                if let document {
                    CurrentDocumentRowView(document: document)
                } else {
                    Text("No PDF open")
                        .foregroundStyle(.secondary)
                }
            }

            WorkspacePluginsSectionView(coordinator: coordinator)

            Section("Recent runs") {
                if coordinator.recentRuns.isEmpty {
                    Text("Completed parses appear here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(coordinator.recentRuns) { run in
                        Button {
                            openRun(run)
                        } label: {
                            RunHistoryRowView(run: run)
                        }
                        .buttonStyle(.plain)
                        .disabled(coordinator.isRunning || coordinator.isInstalling)
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: WorkspaceTheme.standardSpacing) {
                    VStack(alignment: .leading, spacing: WorkspaceTheme.compactSpacing) {
                        Text("Workspace")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Plugins, files, and runs")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .textCase(nil)

                    Spacer()

                    Button("Hide workspace", systemImage: "xmark", action: dismiss)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .help("Hide workspace")
                }
                .padding(WorkspaceTheme.panelPadding)

                Divider()
            }
            .background(.bar)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("On this Mac")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show Runs", action: coordinator.revealRunsFolder)
                    .buttonStyle(.plain)
            }
            .font(.callout)
            .padding(.horizontal, WorkspaceTheme.panelPadding)
            .padding(.vertical, WorkspaceTheme.standardSpacing)
            .background(.bar)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.visible)
        .background(.bar)
    }
}
