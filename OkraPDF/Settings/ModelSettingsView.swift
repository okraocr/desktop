import SwiftUI

struct ModelSettingsView: View {
    @ObservedObject var coordinator: LocalProcessingCoordinator
    @State private var searchText = ""
    @State private var expandedModelID: LocalProviderID?

    private var items: [LocalModelItem] {
        LocalModelItem.items(
            descriptors: coordinator.descriptors,
            availability: coordinator.availabilityByProvider,
            badges: badgesByProvider,
            selected: coordinator.selectedProviderID
        )
    }

    private var visibleItems: [LocalModelItem] {
        guard searchText.isEmpty == false else { return items }
        return items.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.summary.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var badgesByProvider: [LocalProviderID: LocalParserBadge] {
        coordinator.descriptors.reduce(into: [:]) { badges, descriptor in
            badges[descriptor.id] = coordinator.primaryDoctorBadge(for: descriptor.id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsHeader

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    Color.clear
                        .frame(height: 0)
                        .id("models-top")

                    LazyVStack(alignment: .leading, spacing: WorkspaceTheme.sectionSpacing) {
                        ForEach(LocalModelCollection.allCases, id: \.self) { collection in
                            let collectionItems = visibleItems.filter { $0.collection == collection }
                            if collectionItems.isEmpty == false {
                                modelSection(collection, items: collectionItems)
                            }
                        }

                        if visibleItems.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text("No matching models")
                                    .font(.headline)
                                Text("Try a different model name.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                        }
                    }
                    .padding(24)
                }
                .workspacePanelTextRendering()
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo("models-top", anchor: .top)
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search models")
        .onAppear {
            coordinator.refreshAvailability()
            coordinator.refreshOllamaModels()
        }
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local Models")
                .font(.largeTitle.bold())
            Text("Choose what Parse uses and install optional local models. okraPDF selects a healthy default for this Mac, but never downloads a model until you ask.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Label("Active: \(coordinator.selectedDescriptor.name)", systemImage: "checkmark.circle.fill")
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("Runs locally")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private func modelSection(
        _ collection: LocalModelCollection,
        items: [LocalModelItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(collection.rawValue)
                .font(.headline)
            ForEach(items) { item in
                LocalModelCard(
                    item: item,
                    coordinator: coordinator,
                    expandedModelID: $expandedModelID
                )
            }
        }
    }
}

private struct LocalModelCard: View {
    let item: LocalModelItem
    @ObservedObject var coordinator: LocalProcessingCoordinator
    @Binding var expandedModelID: LocalProviderID?

    private var isBusy: Bool {
        coordinator.isRunning || coordinator.isInstalling || coordinator.redaction.isBusy
    }

    private var isExpanded: Bool { expandedModelID == item.id }

    private var usesOllama: Bool {
        item.id == .ollama || item.id == .hybridAuto
    }

    var body: some View {
        cardContent
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(cardBorder)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(item.accessibilityDescription)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            modelSummary

            if isExpanded {
                selectedModelDetail
            }
        }
    }

    private var modelSummary: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.title3)
                .foregroundStyle(modelIconColor)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                modelTitle

                Text(item.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                modelStatus
            }

            Spacer(minLength: 8)

            modelAction
        }
    }

    private var modelTitle: some View {
        HStack(spacing: 7) {
            Text(item.name)
                .font(.headline)
            if item.badge == .recommendedForThisMac {
                settingsBadge("Recommended")
            } else if let badge = item.badge {
                settingsBadge(badge.rawValue)
            }
            if item.isSelected {
                settingsBadge("Active", emphasized: true)
            }
        }
    }

    private var modelStatus: some View {
        HStack(spacing: 12) {
            Text(item.statusMessage)
            if let downloadSizeBytes = item.downloadSizeBytes, item.canInstall {
                Text(downloadSizeBytes, format: .byteCount(style: .file))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var modelIconColor: Color {
        item.isRunnable ? WorkspaceTheme.brand : .secondary
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(borderColor, lineWidth: item.isSelected ? 1.5 : 1)
    }

    private var borderColor: Color {
        item.isSelected ? WorkspaceTheme.brand.opacity(0.75) : Color.secondary.opacity(0.18)
    }

    @ViewBuilder
    private var modelAction: some View {
        if item.isSelected, item.isRunnable {
            HStack(spacing: 8) {
                Label("Active", systemImage: "checkmark")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(WorkspaceTheme.brand)
                if usesOllama {
                    Button("Configure") {
                        expandedModelID = isExpanded ? nil : item.id
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else if item.isRunnable {
            Button("Use Model") {
                coordinator.selectedProviderID = item.id
                expandedModelID = nil
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)
        } else if item.canInstall {
            Button(usesOllama ? "Configure" : "Review & Install") {
                coordinator.selectedProviderID = item.id
                expandedModelID = isExpanded ? nil : item.id
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)
        }
    }

    @ViewBuilder
    private var selectedModelDetail: some View {
        if usesOllama {
            Divider()
            OllamaIntegrationView(coordinator: coordinator)
        }

        if usesOllama == false && (item.canInstall || coordinator.isInstalling) {
            Divider()
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

    private func settingsBadge(_ title: String, emphasized: Bool = false) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(emphasized ? WorkspaceTheme.brand : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                emphasized ? WorkspaceTheme.brand.opacity(0.12) : Color.secondary.opacity(0.1),
                in: .capsule
            )
    }
}
