import Sparkle

/// Owns the Sparkle updater for the app. Sparkle provides the whole
/// click-to-restart flow: background checks against the appcast, download,
/// EdDSA signature verification, install, and relaunch.
final class SparkleUpdaterController: ObservableObject {
    private let controller: SPUStandardUpdaterController

    init() {
        // Debug capture runs launch the bare build product, where Sparkle's
        // startup check fails with a modal alert that stalls the runloop.
        var startsUpdater = true
        #if DEBUG
        if ProcessInfo.processInfo.environment["OKRA_SHELL_CAPTURE_DIR"] != nil {
            startsUpdater = false
        }
        #endif
        controller = SPUStandardUpdaterController(
            startingUpdater: startsUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Manual "Check for Updates…" action. Sparkle shows its own
    /// update-available / up-to-date / error UI for user-initiated checks.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
