import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAssistantPresented = true
    @State private var isNavigationPresented = false
    @State private var navigationDestination: WorkspaceNavigationDestination?
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            WorkspaceCollapsiblePanel(
                isPresented: isNavigationPresented,
                width: WorkspaceTheme.navigationPanelWidth,
                alignment: .trailing
            ) {
                WorkspaceNavigationView(
                    coordinator: state.localProcessing,
                    redaction: state.localProcessing.redaction,
                    destination: $navigationDestination,
                    openRun: state.openRun,
                    dismiss: { isNavigationPresented = false }
                )
                .overlay(alignment: .trailing) {
                    Divider()
                }
            }

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

            WorkspaceCollapsiblePanel(
                isPresented: isAssistantPresented,
                width: WorkspaceTheme.assistantPanelWidth,
                alignment: .leading
            ) {
                AssistantPanelView(
                    document: state.selectedDocument,
                    importError: state.importError,
                    coordinator: state.localProcessing,
                    conversation: state.conversation,
                    parse: state.parseSelectedDocument,
                    revealPDF: state.revealSelectedPDF,
                    openPDF: state.openPDFPicker,
                    showPlugin: presentPlugin,
                    showActivity: presentActivity,
                    dismiss: toggleAssistant
                )
                .overlay(alignment: .leading) {
                    Divider()
                }
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
        .sheet(isPresented: setupGuideIsPresented) {
            SetupGuideView(
                coordinator: state.localProcessing,
                close: state.dismissSetupGuide,
                openPDF: state.openPDFPicker
            )
        }
        .toolbar {
            WorkspaceToolbarContent(
                document: state.selectedDocument,
                isAssistantPresented: isAssistantPresented,
                isNavigationPresented: isNavigationPresented,
                coordinator: state.localProcessing,
                toggleAssistant: toggleAssistant,
                toggleNavigation: toggleNavigation,
                openPDF: state.openPDFPicker,
                revealPDF: state.revealSelectedPDF
            )
        }
        .animation(panelAnimation, value: isAssistantPresented)
        .animation(panelAnimation, value: isNavigationPresented)
    }

    private func toggleAssistant() {
        isAssistantPresented.toggle()
    }

    private func toggleNavigation() {
        isNavigationPresented.toggle()
    }

    private func presentPlugin(_ plugin: AssistantPlugin) {
        navigationDestination = .plugin(plugin)
        isNavigationPresented = true
        isAssistantPresented = false
    }

    private func presentActivity(_ activity: WorkspaceActivity) {
        navigationDestination = .activity(activity)
        isNavigationPresented = true
        isAssistantPresented = false
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
