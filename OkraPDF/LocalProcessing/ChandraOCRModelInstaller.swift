import Foundation

struct ChandraOCRModelInstaller: ChandraOCRModelInstalling {
    private let downloader: any ChandraOCRModelDownloading

    init(downloader: any ChandraOCRModelDownloading = ChandraOCRModelDownloader()) {
        self.downloader = downloader
    }

    func install(
        runtime: ChandraOCRRuntime,
        scriptURL: URL,
        progress: @escaping @Sendable (LocalProviderSetupProgress) -> Void
    ) async throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: runtime.readyMarkerURL.path) {
            try fileManager.removeItem(at: runtime.readyMarkerURL)
        }
        progress(
            LocalProviderSetupProgress(
                phase: .preparing,
                fraction: nil,
                message: "Preparing the private Chandra OCR runtime…"
            )
        )
        try fileManager.createDirectory(at: runtime.rootURL, withIntermediateDirectories: true)

        progress(
            LocalProviderSetupProgress(
                phase: .installingRuntime,
                fraction: nil,
                message: "Installing the pinned MLX runtime…"
            )
        )
        _ = try await LocalCommandRunner.runAsync(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: [scriptURL.path, runtime.rootURL.path]
        )
        try Task.checkCancellation()

        progress(
            LocalProviderSetupProgress(
                phase: .downloadingModel,
                fraction: 0,
                message: "Downloading Chandra OCR 2…"
            )
        )
        try await downloader.downloadModel(to: runtime.modelURL, progress: progress)
        try Task.checkCancellation()

        try ChandraOCRReadyMarker.current().write(to: runtime.readyMarkerURL)
        progress(
            LocalProviderSetupProgress(
                phase: .ready,
                fraction: 1,
                message: "Chandra OCR 2 is ready offline."
            )
        )
    }
}
