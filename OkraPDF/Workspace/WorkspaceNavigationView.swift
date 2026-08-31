import SwiftUI

/// Grouped left navigation for local capabilities and activity.
///
/// The root is deliberately shallow: installable plugins live under Plugins,
/// while run history lives under Activity. Selecting a row replaces the root
/// with one focused destination and a clear back path.
struct WorkspaceNavigationView: View {
    @ObservedObject var coordinator: LocalProcessingCoordinator
    @ObservedObject var redaction: PresidioRedactionCoordinator
    @Binding var destination: WorkspaceNavigationDestination?
    let openRun: (LocalProcessingRun) -> Void
    let dismiss: () -> Void

    var body: some View {
        Group {
            if let destination {
                destinationView(destination)
            } else {
                navigationRoot
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            header
        }
        .background(.bar)
        .onAppear {
            coordinator.refreshAvailability()
            redaction.refreshAvailability()
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: WorkspaceTheme.standardSpacing) {
                if destination != nil {
                    Button("Back to workspace", systemImage: "chevron.left") {
                        destination = nil
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .help("Back to workspace")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(destination?.name ?? "Workspace")
                        .font(.headline)
                    Text(destination?.section.rawValue ?? "On this Mac")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Hide navigation", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .help("Hide navigation")
            }
            .padding(WorkspaceTheme.panelPadding)

            Divider()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var navigationRoot: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WorkspaceTheme.sectionSpacing) {
                navigationSection(
                    title: WorkspaceNavigationSection.plugins.rawValue,
                    note: "Capabilities you can configure and run locally"
                ) {
                    ForEach(WorkspacePlugin.allCases) { plugin in
                        if plugin != WorkspacePlugin.allCases.first { Divider() }
                        navigationButton(
                            destination: .plugin(plugin),
                            statusMessage: pluginStatusMessage(plugin),
                            statusImage: pluginStatusImage(plugin)
                        )
                    }
                }

                navigationSection(
                    title: WorkspaceNavigationSection.activity.rawValue,
                    note: "History and outputs created on this Mac"
                ) {
                    navigationButton(
                        destination: .activity(.runs),
                        statusMessage: runsStatusMessage,
                        statusImage: "clock.arrow.circlepath"
                    )
                }
            }
            .padding(WorkspaceTheme.panelPadding)
        }
        .workspacePanelTextRendering()
    }

    private func navigationSection<Content: View>(
        title: String,
        note: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: WorkspaceTheme.compactSpacing) {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text(note)
                .font(.caption)
                .foregroundStyle(.tertiary)

            VStack(spacing: 0, content: content)
                .background(
                    Color.primary.opacity(0.035),
                    in: .rect(cornerRadius: WorkspaceTheme.cardRadius)
                )
        }
    }

    private func navigationButton(
        destination: WorkspaceNavigationDestination,
        statusMessage: String,
        statusImage: String
    ) -> some View {
        Button {
            self.destination = destination
        } label: {
            WorkspaceNavigationRowView(
                destination: destination,
                statusMessage: statusMessage,
                statusImage: statusImage
            )
        }
        .buttonStyle(.plain)
    }

    private func destinationView(_ destination: WorkspaceNavigationDestination) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WorkspaceTheme.sectionSpacing) {
                switch destination {
                case .plugin(.extract):
                    Text("Choose the parser Extract uses. Downloads, model selection, and installation progress stay with this plugin.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ParserPluginSettingsView(coordinator: coordinator)
                case .plugin(.redact):
                    RedactPluginSetupView(
                        coordinator: coordinator,
                        redaction: redaction
                    )
                case .activity(.runs):
                    RunsActivityView(
                        coordinator: coordinator,
                        openRun: openRun
                    )
                }
            }
            .padding(WorkspaceTheme.panelPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .workspacePanelTextRendering()
    }

    private func pluginStatusMessage(_ plugin: WorkspacePlugin) -> String {
        switch plugin {
        case .extract:
            if coordinator.isInstalling {
                return coordinator.setupProgress?.message ?? "Installing parser…"
            }
            return "\(coordinator.selectedDescriptor.name) · \(coordinator.selectedAvailability.message)"
        case .redact:
            if redaction.isInstalling {
                return redaction.setupProgress?.message ?? "Installing Presidio…"
            }
            return redaction.availability.message
        }
    }

    private func pluginStatusImage(_ plugin: WorkspacePlugin) -> String {
        switch plugin {
        case .extract:
            if coordinator.isInstalling { return "arrow.down.circle" }
            return availabilityImage(coordinator.selectedAvailability)
        case .redact:
            if redaction.isInstalling { return "arrow.down.circle" }
            return availabilityImage(redaction.availability)
        }
    }

    private var runsStatusMessage: String {
        let count = coordinator.recentRuns.count
        return count == 1 ? "1 recent local run" : "\(count) recent local runs"
    }

    private func availabilityImage(_ availability: LocalProviderAvailability) -> String {
        switch availability {
        case .ready:
            return "checkmark.circle.fill"
        case .simulated:
            return "exclamationmark.triangle.fill"
        case .setupRequired:
            return "arrow.down.circle"
        case .unavailable:
            return "slash.circle"
        }
    }
}

private struct WorkspaceNavigationRowView: View {
    let destination: WorkspaceNavigationDestination
    let statusMessage: String
    let statusImage: String

    var body: some View {
        HStack(alignment: .center, spacing: WorkspaceTheme.standardSpacing) {
            Image(systemName: destination.systemImage)
                .foregroundStyle(WorkspaceTheme.brand)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(destination.name)
                    .font(.callout)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Image(systemName: statusImage)
                        .accessibilityHidden(true)
                    Text(statusMessage)
                        .lineLimit(2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, WorkspaceTheme.standardSpacing)
        .padding(.vertical, WorkspaceTheme.standardSpacing)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(destination.section.rawValue), \(destination.name), \(statusMessage)")
        .accessibilityHint("Opens \(destination.name)")
    }
}

private struct RunsActivityView: View {
    @ObservedObject var coordinator: LocalProcessingCoordinator
    let openRun: (LocalProcessingRun) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
            Text("Parse history and saved outputs")
                .font(.headline)
            Text("Runs are activity, not plugins. They stay under Okra/Runs on this Mac.")
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
    }
}
