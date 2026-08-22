import Foundation

enum LocalProviderPaths {
    static var applicationSupportRoot: URL {
        applicationSupportRoot(
            applicationSupportDirectory: FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
        )
    }

    static func applicationSupportRoot(applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory.appendingPathComponent("Okra", isDirectory: true)
    }

    static var runsRoot: URL {
        applicationSupportRoot.appendingPathComponent("Runs", isDirectory: true)
    }

    static func runsRoot(applicationSupportDirectory: URL) -> URL {
        applicationSupportRoot(applicationSupportDirectory: applicationSupportDirectory)
            .appendingPathComponent("Runs", isDirectory: true)
    }

    static var providersRoot: URL {
        applicationSupportRoot.appendingPathComponent("Providers", isDirectory: true)
    }

    static func providersRoot(applicationSupportDirectory: URL) -> URL {
        applicationSupportRoot(applicationSupportDirectory: applicationSupportDirectory)
            .appendingPathComponent("Providers", isDirectory: true)
    }

    static var dotsOCRRoot: URL {
        providersRoot.appendingPathComponent("dots-ocr", isDirectory: true)
    }

    static var dotsOCRPython: URL {
        dotsOCRRoot
            .appendingPathComponent("venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python")
    }

    static var dotsOCRModel: URL {
        dotsOCRRoot.appendingPathComponent("model", isDirectory: true)
    }

    static var dotsOCRReadyMarker: URL {
        dotsOCRRoot.appendingPathComponent(".ready")
    }

    static var unlimitedOCRRoot: URL {
        providersRoot.appendingPathComponent("unlimited-ocr", isDirectory: true)
    }

    static var unlimitedOCRPython: URL {
        unlimitedOCRRoot
            .appendingPathComponent("venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python")
    }

    static var unlimitedOCRModel: URL {
        unlimitedOCRRoot.appendingPathComponent("model", isDirectory: true)
    }

    static var unlimitedOCRReadyMarker: URL {
        unlimitedOCRRoot.appendingPathComponent(".ready")
    }

    static var chandraOCRRoot: URL {
        providersRoot.appendingPathComponent("chandra-ocr-2", isDirectory: true)
    }

    static var chandraOCRPython: URL {
        chandraOCRRoot
            .appendingPathComponent("venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python")
    }

    static var chandraOCRModel: URL {
        chandraOCRRoot.appendingPathComponent("model", isDirectory: true)
    }

    static var chandraOCRReadyMarker: URL {
        chandraOCRRoot.appendingPathComponent(".ready")
    }

    static func runDirectory(runsRoot: URL = runsRoot, runID: String) -> URL {
        runsRoot.appendingPathComponent(runID, isDirectory: true)
    }
}
