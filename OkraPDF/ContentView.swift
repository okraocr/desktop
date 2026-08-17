import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var layout = WorkspaceLayoutState()
    @FocusState private var focusedPanelToggle: WorkspacePanel?
    @State private var isDropTargeted = false

    var body: some View {
        GeometryReader { proxy in
            workspace(availableWidth: proxy.size.width)
        }
        .background(.background)
        .tint(WorkspaceTheme.brand)
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $isDropTargeted,
            perform: handleDrop
        )
        .alert("Unable to Open PDF", isPresented: importErrorIsPresented) {
            Button("OK", role: .cancel, action: state.dismissImportError)
        } message: {
            Text(state.importError ?? "The PDF could not be opened.")
        }
        .sheet(isPresented: setupGuideIsPresented) {
            SetupGuideView(
                coordinator: state.localProcessing,
                close: state.dismissSetupGuide,
                openPDF: state.openPDFPicker
            )
        }
    }

    private func workspace(availableWidth: Double) -> some View {
        let presentation = layout.presentation(for: availableWidth)

        return HStack(spacing: 0) {
            WorkspaceCollapsiblePanel(
                isPresented: presentation.isSidebarPresented,
                width: WorkspaceTheme.sidebarWidth,
                alignment: .trailing
            ) {
                WorkspaceSidebarView(
                    document: state.selectedDocument,
                    coordinator: state.localProcessing,
                    openRun: state.openRun,
                    dismiss: { toggle(.sidebar, availableWidth: availableWidth) }
                )
                .overlay(alignment: .trailing) {
                    Divider()
                }
            }

            WorkspaceLeadingRailView(
                isSidebarPresented: presentation.isSidebarPresented,
                coordinator: state.localProcessing,
                focusedPanelToggle: $focusedPanelToggle,
                toggleSidebar: { toggle(.sidebar, availableWidth: availableWidth) },
                openPDF: state.openPDFPicker,
                revealRuns: state.localProcessing.revealRunsFolder
            )

            Divider()

            DocumentWorkspaceView(
                document: state.selectedDocument,
                isDropTargeted: isDropTargeted,
                coordinator: state.localProcessing,
                redaction: state.localProcessing.redaction,
                canOpenPDF: state.canOpenPDF,
                openPDF: state.openPDFPicker,
                openSetupGuide: state.presentSetupGuide
            )
            .frame(minWidth: WorkspaceTheme.readerMinimumWidth)
            .layoutPriority(1)

            Divider()

            WorkspaceTrailingRailView(
                documentIsOpen: state.selectedDocument != nil,
                isInspectorPresented: presentation.isInspectorPresented,
                coordinator: state.localProcessing,
                focusedPanelToggle: $focusedPanelToggle,
                toggleInspector: { toggle(.inspector, availableWidth: availableWidth) },
                revealPDF: state.revealSelectedPDF
            )

            WorkspaceCollapsiblePanel(
                isPresented: presentation.isInspectorPresented,
                width: WorkspaceTheme.inspectorWidth,
                alignment: .leading
            ) {
                ExtractionInspectorView(
                    document: state.selectedDocument,
                    importError: state.importError,
                    coordinator: state.localProcessing,
                    parse: state.parseSelectedDocument,
                    revealPDF: state.revealSelectedPDF,
                    dismiss: { toggle(.inspector, availableWidth: availableWidth) }
                )
                .overlay(alignment: .leading) {
                    Divider()
                }
            }
        }
        .toolbar {
            WorkspaceToolbarContent(
                document: state.selectedDocument,
                isSidebarPresented: presentation.isSidebarPresented,
                isInspectorPresented: presentation.isInspectorPresented,
                coordinator: state.localProcessing,
                toggleSidebar: { toggle(.sidebar, availableWidth: availableWidth) },
                toggleInspector: { toggle(.inspector, availableWidth: availableWidth) },
                openPDF: state.openPDFPicker,
                revealPDF: state.revealSelectedPDF
            )
        }
        .animation(panelAnimation, value: presentation.isSidebarPresented)
        .animation(panelAnimation, value: presentation.isInspectorPresented)
    }

    private var panelAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)
    }

    private var importErrorIsPresented: Binding<Bool> {
        Binding(
            get: { state.importError != nil },
            set: { isPresented in
                if isPresented == false {
                    state.dismissImportError()
                }
            }
        )
    }

    private var setupGuideIsPresented: Binding<Bool> {
        Binding(
            get: { state.showsSetupGuide },
            set: { isPresented in
                if isPresented == false {
                    state.dismissSetupGuide()
                }
            }
        )
    }

    private func toggle(_ panel: WorkspacePanel, availableWidth: Double) {
        layout.toggle(panel, availableWidth: availableWidth)
        focusedPanelToggle = nil
        Task { @MainActor in
            focusedPanelToggle = panel
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard state.localProcessing.isRunning == false,
              state.localProcessing.isInstalling == false,
              state.localProcessing.redaction.isBusy == false,
              let provider = providers.first(where: {
                  $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
              }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let url = droppedFileURL(from: item) else { return }
            Task { @MainActor in
                state.openPDF(url)
            }
        }
        return true
    }

    private func droppedFileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url.standardizedFileURL
        }
        if let data = item as? Data {
            if let url = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSURL.self, from: data) {
                return (url as URL).standardizedFileURL
            }
            if let string = String(data: data, encoding: .utf8) {
                return droppedFileURL(from: string as NSSecureCoding)
            }
        }
        if let string = item as? String {
            if let url = URL(string: string), url.isFileURL {
                return url.standardizedFileURL
            }
            return URL(fileURLWithPath: string).standardizedFileURL
        }
        return nil
    }
}
