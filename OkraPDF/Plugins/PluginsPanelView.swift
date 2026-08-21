import SwiftUI

/// The single in-shell home for local plugin status, configuration, and installation.
/// Assistant cards can link here without owning any setup UI, and coordinator-
/// owned tasks keep running when this panel is hidden.
struct PluginsPanelView: View {
    @ObservedObject var coordinator: LocalProcessingCoordinator
    @ObservedObject var redaction: PresidioRedactionCoordinator
    @Binding var selection: AssistantPlugin
    let dismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
                ForEach(AssistantPlugin.allCases) { plugin in
                    VStack(alignment: .leading, spacing: WorkspaceTheme.compactSpacing) {
                        Button {
                            selection = plugin
                        } label: {
                            PluginCatalogRowView(
                                plugin: plugin,
                                statusMessage: statusMessage(for: plugin),
                                statusImage: statusImage(for: plugin),
                                isSelected: selection == plugin
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == plugin ? [.isSelected] : [])

                        if selection == plugin {
                            pluginDetail(plugin)
                                .padding(.horizontal, WorkspaceTheme.standardSpacing)
                                .padding(.bottom, WorkspaceTheme.compactSpacing)
                        }
                    }
                }
            }
            .padding(WorkspaceTheme.standardSpacing)
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
            HStack(alignment: .top, spacing: WorkspaceTheme.standardSpacing) {
                VStack(alignment: .leading, spacing: WorkspaceTheme.compactSpacing) {
                    Text("Plugins")
                        .font(.headline)
                    Text("Local tools · on this Mac")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Hide plugins", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .help("Hide plugins")
            }
            .padding(WorkspaceTheme.panelPadding)

            Divider()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func pluginDetail(_ plugin: AssistantPlugin) -> some View {
        switch plugin {
        case .extract:
            VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
                Text("Choose the local parser Extract will use. Downloads, model selection, and installation progress stay on this page.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ParserPluginSettingsView(coordinator: coordinator)
            }
        case .redact:
            RedactPluginSetupView(
                coordinator: coordinator,
                redaction: redaction
            )
        case .runs:
            VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
                WorkspaceNoticeView(
                    message: "Runs is built in and ready.",
                    systemImage: "checkmark.circle.fill",
                    color: WorkspaceTheme.brand
                )
                Text("Parse history and outputs remain under Okra/Runs on this Mac. Runs has no dependencies to install.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Show Runs Folder", action: coordinator.revealRunsFolder)
                    .buttonStyle(.bordered)
            }
        }
    }

    private func statusMessage(for plugin: AssistantPlugin) -> String {
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
        case .runs:
            let count = coordinator.recentRuns.count
            return count == 1 ? "1 local run" : "\(count) local runs"
        }
    }

    private func statusImage(for plugin: AssistantPlugin) -> String {
        switch plugin {
        case .extract:
            if coordinator.isInstalling { return "arrow.down.circle" }
            return availabilityImage(coordinator.selectedAvailability)
        case .redact:
            if redaction.isInstalling { return "arrow.down.circle" }
            return availabilityImage(redaction.availability)
        case .runs:
            return "checkmark.circle.fill"
        }
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

private struct PluginCatalogRowView: View {
    let plugin: AssistantPlugin
    let statusMessage: String
    let statusImage: String
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: WorkspaceTheme.standardSpacing) {
            Image(systemName: plugin.systemImage)
                .foregroundStyle(isSelected ? WorkspaceTheme.brand : .secondary)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.name)
                    .font(.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: statusImage)
                .foregroundStyle(statusImage == "checkmark.circle.fill" ? WorkspaceTheme.brand : .secondary)
                .accessibilityHidden(true)
        }
        .padding(WorkspaceTheme.standardSpacing)
        .background(
            isSelected ? WorkspaceTheme.brand.opacity(0.12) : Color.clear,
            in: .rect(cornerRadius: WorkspaceTheme.cardRadius)
        )
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(plugin.name), \(statusMessage)")
    }
}
