import Foundation

struct ChandraOCRReadyMarker: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let runtimeLockVersion = "python>=3.10|mlx-vlm==0.6.6|huggingface-hub==1.24.0|v1"

    let schemaVersion: Int
    let modelRevision: String
    let runtimeLockVersion: String
    let installedAt: String

    static func current(installedAt: Date = .now) -> ChandraOCRReadyMarker {
        ChandraOCRReadyMarker(
            schemaVersion: schemaVersion,
            modelRevision: ChandraOCRModelManifest.revision,
            runtimeLockVersion: runtimeLockVersion,
            installedAt: installedAt.ISO8601Format()
        )
    }

    var matchesCurrentRuntime: Bool {
        schemaVersion == Self.schemaVersion
            && modelRevision == ChandraOCRModelManifest.revision
            && runtimeLockVersion == Self.runtimeLockVersion
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    static func read(from url: URL) -> ChandraOCRReadyMarker? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ChandraOCRReadyMarker.self, from: data)
    }
}

struct ChandraOCRRuntime: Sendable {
    let rootURL: URL
    let pythonURL: URL
    let modelURL: URL
    let readyMarkerURL: URL
    let cacheURL: URL
    let workerURL: URL?
    let isSimulation: Bool

    var hasCurrentReadyMarker: Bool {
        guard let marker = ChandraOCRReadyMarker.read(from: readyMarkerURL) else {
            return false
        }
        return marker.matchesCurrentRuntime
    }

    var hasCurrentModelArtifacts: Bool {
        ChandraOCRModelManifest.artifacts.allSatisfy { artifact in
            let artifactURL = modelURL.appendingPathComponent(artifact.path)
            guard let attributes = try? FileManager.default.attributesOfItem(
                atPath: artifactURL.path
            ), let size = attributes[.size] as? NSNumber else {
                return false
            }
            return size.int64Value == artifact.size
        }
    }

    static func installed(workerURL: URL?) -> ChandraOCRRuntime {
        ChandraOCRRuntime(
            rootURL: LocalProviderPaths.chandraOCRRoot,
            pythonURL: LocalProviderPaths.chandraOCRPython,
            modelURL: LocalProviderPaths.chandraOCRModel,
            readyMarkerURL: LocalProviderPaths.chandraOCRReadyMarker,
            cacheURL: LocalProviderPaths.chandraOCRRoot
                .appendingPathComponent("huggingface", isDirectory: true),
            workerURL: workerURL,
            isSimulation: false
        )
    }

    static func simulated(workerURL: URL?) -> ChandraOCRRuntime {
        let pythonURL = TrustedPythonInterpreter.firstAvailable()
            ?? URL(fileURLWithPath: "/usr/bin/python3")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("okra-chandra-ocr-2-simulation", isDirectory: true)
        return ChandraOCRRuntime(
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
