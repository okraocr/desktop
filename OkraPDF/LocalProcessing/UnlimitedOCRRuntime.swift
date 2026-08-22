import Foundation

struct UnlimitedOCRRuntime: Sendable {
    let rootURL: URL
    let pythonURL: URL
    let modelURL: URL
    let readyMarkerURL: URL
    let cacheURL: URL
    let workerURL: URL?
    let isSimulation: Bool

    static func installed(workerURL: URL?) -> UnlimitedOCRRuntime {
        UnlimitedOCRRuntime(
            rootURL: LocalProviderPaths.unlimitedOCRRoot,
            pythonURL: LocalProviderPaths.unlimitedOCRPython,
            modelURL: LocalProviderPaths.unlimitedOCRModel,
            readyMarkerURL: LocalProviderPaths.unlimitedOCRReadyMarker,
            cacheURL: LocalProviderPaths.unlimitedOCRRoot
                .appendingPathComponent("huggingface", isDirectory: true),
            workerURL: workerURL,
            isSimulation: false
        )
    }

    static func simulated(workerURL: URL?) -> UnlimitedOCRRuntime {
        let pythonURL = TrustedPythonInterpreter.firstAvailable()
            ?? URL(fileURLWithPath: "/usr/bin/python3")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("okra-unlimited-ocr-simulation", isDirectory: true)
        return UnlimitedOCRRuntime(
            rootURL: root,
            pythonURL: pythonURL,
            modelURL: root.appendingPathComponent("model", isDirectory: true),
            readyMarkerURL: root.appendingPathComponent(".ready"),
            cacheURL: root.appendingPathComponent("huggingface", isDirectory: true),
            workerURL: workerURL,
            isSimulation: true
        )
    }
}
