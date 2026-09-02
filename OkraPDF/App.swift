import AppKit
import SwiftUI

@main
struct okraPDFApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var updaterController = SparkleUpdaterController()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Okra") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 960, minHeight: 680)
                .onOpenURL(perform: appState.handleOpenURL)
        }
        .defaultSize(width: 1_320, height: 820)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open PDF…", action: appState.openPDFPicker)
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(appState.canOpenPDF == false)
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…", action: updaterController.checkForUpdates)
            }
            CommandGroup(after: .help) {
                Button("Copy Local Parser Diagnostics", action: appState.copyLocalParserDiagnostics)
            }
        }

        Settings {
            DesktopSettingsView(coordinator: appState.localProcessing)
        }
    }
}
