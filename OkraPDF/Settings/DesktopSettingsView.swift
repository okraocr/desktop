import SwiftUI

struct DesktopSettingsView: View {
    @ObservedObject var coordinator: LocalProcessingCoordinator
    @AppStorage(DesktopSettingsSection.selectionDefaultsKey)
    private var selectedSectionRawValue = DesktopSettingsSection.models.rawValue

    private var selectedSection: DesktopSettingsSection {
        DesktopSettingsSection(rawValue: selectedSectionRawValue) ?? .models
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, idealWidth: 980, minHeight: 620, idealHeight: 720)
        .tint(WorkspaceTheme.brand)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            BrandMarkView(size: 52)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 8)

            Divider()

            ForEach(DesktopSettingsSection.allCases) { section in
                Button {
                    selectedSectionRawValue = section.rawValue
                } label: {
                    Label(section.title, systemImage: section.systemImage)
                        .font(.callout.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            section == selectedSection
                                ? WorkspaceTheme.brand.opacity(0.18)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(section == selectedSection ? .isSelected : [])
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(width: 210)
        .background(.bar)
        .workspacePanelTextRendering()
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedSection {
        case .general:
            generalSettings
        case .models:
            ModelSettingsView(coordinator: coordinator)
        case .redaction:
            settingsPage(title: "Redaction", subtitle: "Install and configure local PII detection.") {
                RedactPluginSetupView(
                    coordinator: coordinator,
                    redaction: coordinator.redaction
                )
            }
        case .advanced:
            settingsPage(title: "Advanced", subtitle: "Diagnostics and review behavior.") {
                Toggle("Show source boxes after parsing", isOn: $coordinator.showsPDFBoundingBoxes)
                Button("Copy Local Parser Diagnostics", action: coordinator.copyDoctorReport)
                    .buttonStyle(.bordered)
            }
        case .about:
            aboutSettings
        }
    }

    private var generalSettings: some View {
        settingsPage(
            title: "General",
            subtitle: "Private, source-preserving PDF processing on this Mac."
        ) {
            LabeledContent("Parse model", value: coordinator.selectedDescriptor.name)
            LabeledContent("Processing", value: "Local")
            LabeledContent("PDF uploads", value: "Never")
            LabeledContent("Model downloads", value: "Only when requested")
        }
    }

    private var aboutSettings: some View {
        settingsPage(title: "About okraPDF", subtitle: "Read and parse PDFs privately on your Mac.") {
            HStack(spacing: 14) {
                BrandMarkView(size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Desktop")
                        .font(.title2.bold())
                    Text("Version \(appVersion)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func settingsPage<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.largeTitle.bold())
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 14, content: content)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .workspacePanelTextRendering()
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Development"
    }
}
