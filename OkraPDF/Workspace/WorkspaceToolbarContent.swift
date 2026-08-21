import SwiftUI

struct WorkspaceToolbarContent: ToolbarContent {
    let document: LocalPDFDocument?
    let isAssistantPresented: Bool
    let isPluginsPresented: Bool
    @ObservedObject var coordinator: LocalProcessingCoordinator
    let toggleAssistant: () -> Void
    let togglePlugins: () -> Void
    let openPDF: () -> Void
    let revealPDF: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            BrandMarkView(size: 24)
        }

        ToolbarItem(placement: .navigation) {
            Toggle(
                isOn: Binding(
                    get: { isPluginsPresented },
                    set: { _ in togglePlugins() }
                )
            ) {
                Label("Plugins", systemImage: "puzzlepiece.extension")
            }
            .toggleStyle(.button)
            .labelStyle(.iconOnly)
            .help(isPluginsPresented ? "Hide plugins" : "Show plugins")
            .accessibilityValue("Selected parser: \(coordinator.selectedDescriptor.name)")
        }

        ToolbarItem(placement: .principal) {
            Text(document?.fileName ?? "PDF reader")
                .lineLimit(1)
                .truncationMode(.middle)
            .accessibilityLabel(document?.fileName ?? "PDF reader, no document open")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if coordinator.pdfBoundingBoxOverlays.isEmpty == false {
                Toggle(isOn: $coordinator.showsPDFBoundingBoxes) {
                    Label("Show extraction boxes", systemImage: "viewfinder.rectangular")
                }
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .help(
                    coordinator.showsPDFBoundingBoxes
                        ? "Hide extraction boxes"
                        : "Show extraction boxes"
                )
                .accessibilityValue(
                    coordinator.showsPDFBoundingBoxes
                        ? "\(coordinator.pdfBoundingBoxOverlays.count) extraction boxes visible"
                        : "Hidden"
                )
            }

            if document != nil {
                Button(
                    "Reveal source PDF in Finder",
                    systemImage: "arrow.forward.circle",
                    action: revealPDF
                )
                .labelStyle(.iconOnly)
                .help("Reveal the source PDF in Finder")
            }

            Button("Open PDF…", systemImage: "folder", action: openPDF)
                .disabled(coordinator.isRunning || coordinator.isInstalling)

            Toggle(
                isOn: Binding(
                    get: { isAssistantPresented },
                    set: { _ in toggleAssistant() }
                )
            ) {
                Label("Assistant", systemImage: "sidebar.right")
            }
            .toggleStyle(.button)
            .labelStyle(.iconOnly)
            .help(isAssistantPresented ? "Hide assistant" : "Show assistant")
        }
    }
}
