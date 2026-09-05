import Foundation

struct UnlimitedOCRModelInstaller: UnlimitedOCRModelInstalling {
    private let downloader: any UnlimitedOCRModelDownloading

    init(downloader: any UnlimitedOCRModelDownloading = UnlimitedOCRModelDownloader()) {
        self.downloader = downloader
    }

    func install(
        runtime: UnlimitedOCRRuntime,
        scriptURL: URL,
        progress: @escaping @Sendable (LocalProviderSetupProgress) -> Void
    ) async throws {
        progress(
            LocalProviderSetupProgress(
                phase: .preparing,
                fraction: nil,
                message: "Preparing the private model runtime…"
            )
        )
        try FileManager.default.createDirectory(at: runtime.rootURL, withIntermediateDirectories: true)

        progress(
            LocalProviderSetupProgress(
                phase: .installingRuntime,
                fraction: nil,
                message: "Installing the pinned MLX runtime…"
            )
        )
        guard let pythonURL = TrustedPythonInterpreter.firstAvailable() else {
            throw LocalProcessingError.trustedPythonUnavailable
        }
        try await ProviderRuntimeInstaller.run(
            scriptURL: scriptURL, rootURL: runtime.rootURL, pythonURL: pythonURL
        )
        try Task.checkCancellation()

        progress(
            LocalProviderSetupProgress(
                phase: .downloadingModel,
                fraction: 0,
                message: "Downloading Baidu Unlimited-OCR…"
            )
        )
        try await downloader.downloadModel(to: runtime.modelURL, progress: progress)
        try Task.checkCancellation()

        try "\(Date.now.ISO8601Format())\n".write(
            to: runtime.readyMarkerURL,
            atomically: true,
            encoding: .utf8
        )
        progress(
            LocalProviderSetupProgress(
                phase: .ready,
                fraction: 1,
                message: "Baidu Unlimited-OCR is ready offline."
            )
        )
    }
}
