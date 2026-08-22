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

    static func validatedRunDirectory(
        runsRoot: URL = runsRoot,
        runID: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        let allowedCharacters = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "._-")
        )
        guard runID.isEmpty == false,
              runID.count <= 128,
              runID != ".",
              runID != "..",
              runID.rangeOfCharacter(from: allowedCharacters.inverted) == nil else {
            throw LocalProviderPathError.invalidRunIdentifier
        }

        let standardizedRoot = runsRoot.standardizedFileURL
        let candidate = runDirectory(runsRoot: standardizedRoot, runID: runID)
            .standardizedFileURL
        guard candidate.deletingLastPathComponent().path == standardizedRoot.path else {
            throw LocalProviderPathError.runDirectoryEscapesRoot
        }

        if let attributes = try? fileManager.attributesOfItem(atPath: candidate.path),
           attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            throw LocalProviderPathError.symbolicRunDirectory
        }

        let resolvedRoot = standardizedRoot.resolvingSymlinksInPath()
        let resolvedCandidate = candidate.resolvingSymlinksInPath()
        guard resolvedCandidate.deletingLastPathComponent().path == resolvedRoot.path else {
            throw LocalProviderPathError.runDirectoryEscapesRoot
        }
        return candidate
    }

    static func validateRunDirectory(
        _ runDirectory: URL,
        runsRoot: URL = runsRoot,
        runID: String,
        fileManager: FileManager = .default
    ) throws {
        let expected = try validatedRunDirectory(
            runsRoot: runsRoot,
            runID: runID,
            fileManager: fileManager
        )
        guard runDirectory.standardizedFileURL.path == expected.path else {
            throw LocalProviderPathError.runDirectoryEscapesRoot
        }
    }
}

enum LocalProviderPathError: LocalizedError {
    case invalidRunIdentifier
    case runDirectoryEscapesRoot
    case symbolicRunDirectory

    var errorDescription: String? {
        switch self {
        case .invalidRunIdentifier:
            return "The saved run identifier is invalid."
        case .runDirectoryEscapesRoot:
            return "The saved run directory is outside Okra's run storage."
        case .symbolicRunDirectory:
            return "Symbolic links cannot be used as Okra run directories."
        }
    }
}
