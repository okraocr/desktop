import SwiftUI

/// The leading Parsers panel.
///
/// Choosing an engine and preparing it lives here; running it lives in the
/// assistant's Extract card on the trailing side. The selected parser expands
/// in place to show whatever it still needs — a download, an Ollama model — so
/// setup happens next to the thing being set up.
struct ParsersPanelView: View {
    @ObservedObject var coordinator: LocalProcessingCoordinator
    let dismiss: () -> Void

    private var items: [ParserPluginItem] {
        ParserPluginItem.items(
            descriptors: coordinator.descriptors,
            availability: coordinator.availabilityByProvider,
            badges: badgesByProvider,
            selected: coordinator.selectedProviderID
        )
    }

    /// The coordinator exposes one badge at a time; the row mapping wants them
    /// keyed by provider.
    private var badgesByProvider: [LocalProviderID: LocalParserBadge] {
        coordinator.descriptors.reduce(into: [:]) { badges, descriptor in
            badges[descriptor.id] = coordinator.primaryDoctorBadge(for: descriptor.id)
        }
    }

    private var isBusy: Bool {
        coordinator.isRunning || coordinator.isInstalling
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: WorkspaceTheme.compactSpacing) {
                        Button {
                            coordinator.selectedProviderID = item.id
                        } label: {
                            ParserPluginRowView(item: item)
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy && item.isSelected == false)
                        .accessibilityLabel(item.accessibilityDescription)
                        .accessibilityAddTraits(item.isSelected ? [.isSelected] : [])

                        if item.isSelected {
                            selectedParserDetail(for: item)
                        }
                    }
                    .padding(.horizontal, WorkspaceTheme.standardSpacing)
                }
            }
            .padding(.vertical, WorkspaceTheme.standardSpacing)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            header
        }
        .background(.bar)
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: WorkspaceTheme.standardSpacing) {
                VStack(alignment: .leading, spacing: WorkspaceTheme.compactSpacing) {
                    Text("Parsers")
                        .font(.headline)
                    Text("Local engines · on this Mac")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Hide parsers", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .help("Hide parsers")
            }
            .padding(WorkspaceTheme.panelPadding)

            Divider()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func selectedParserDetail(for item: ParserPluginItem) -> some View {
        VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
            Text(item.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let verdict = coordinator.doctorVerdict(for: item.id),
               let headline = verdict.reasons.first {
                Text(headline)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if coordinator.selectedProviderUsesOllama {
                OllamaIntegrationView(coordinator: coordinator)
            }

            if item.isRunnable == false || coordinator.isInstalling {
                ProviderSetupView(coordinator: coordinator)
            }

            if item.readiness == .simulated {
                WorkspaceNoticeView(
                    message: "Simulation validates rendering and run persistence. It does not load model weights.",
                    systemImage: "exclamationmark.triangle.fill",
                    color: .orange
                )
            }
        }
        .padding(.leading, WorkspaceTheme.standardSpacing)
        .padding(.bottom, WorkspaceTheme.compactSpacing)
    }
}

/// A single parser row: name, why you'd pick it, and whether it can run now.
struct ParserPluginRowView: View {
    let item: ParserPluginItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WorkspaceTheme.compactSpacing) {
            Image(systemName: item.systemImage)
                .foregroundStyle(item.isRunnable ? WorkspaceTheme.brand : .secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: WorkspaceTheme.compactSpacing) {
                    Text(item.name)
                        .font(.callout)
                        .fontWeight(item.isSelected ? .semibold : .regular)
                        .foregroundStyle(.primary)

                    if let badge = item.badge {
                        Text(badge.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                .quaternary.opacity(0.4),
                                in: .rect(cornerRadius: 4)
                            )
                    }
                }

                Text(item.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, WorkspaceTheme.compactSpacing)
        .padding(.horizontal, WorkspaceTheme.standardSpacing)
        .background(
            item.isSelected ? WorkspaceTheme.brand.opacity(0.12) : Color.clear,
            in: .rect(cornerRadius: WorkspaceTheme.cardRadius)
        )
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
