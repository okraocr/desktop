import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHistoryPresented = false
    @State private var facetMode: FacetWorkspaceMode = .extraction
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            WorkspaceCollapsiblePanel(
                isPresented: isHistoryPresented,
                width: WorkspaceTheme.navigationPanelWidth,
                alignment: .trailing
            ) {
                RunHistoryPanelView(
                    coordinator: state.localProcessing,
                    openRun: state.openRun,
                    dismiss: { isHistoryPresented = false }
                )
                .overlay(alignment: .trailing) {
                    Divider()
                }
            }

            HSplitView {
                DocumentWorkspaceView(
                    document: state.selectedDocument,
                    isDropTargeted: isDropTargeted,
                    facetMode: facetMode,
                    coordinator: state.localProcessing,
                    redaction: state.localProcessing.redaction,
                    canOpenPDF: state.canOpenPDF,
                    openPDF: state.openPDFPicker,
                    openModelSettings: { DesktopSettingsWindow.open(.models) }
                )
                .frame(minWidth: WorkspaceTheme.readerMinimumWidth)
                .layoutPriority(1)

                FacetWorkspaceView(
                    document: state.selectedDocument,
                    coordinator: state.localProcessing,
                    mode: $facetMode,
                    parse: state.parseSelectedDocument,
                    openSettings: DesktopSettingsWindow.open
                )
                .frame(
                    minWidth: WorkspaceTheme.facetMinimumWidth,
                    idealWidth: WorkspaceTheme.facetIdealWidth
                )
            }
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
        .toolbar {
            WorkspaceToolbarContent(
                document: state.selectedDocument,
                isHistoryPresented: isHistoryPresented,
                coordinator: state.localProcessing,
                toggleHistory: toggleHistory,
                openPDF: state.openPDFPicker,
                revealPDF: state.revealSelectedPDF,
                openModelSettings: { DesktopSettingsWindow.open(.models) }
            )
        }
        .animation(panelAnimation, value: isHistoryPresented)
    }

    private func toggleHistory() {
        isHistoryPresented.toggle()
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
