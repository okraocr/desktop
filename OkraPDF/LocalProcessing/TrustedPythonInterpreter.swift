import Foundation

struct TrustedPythonInterpreterPolicy {
    let candidates: [URL]
    let trustedRoots: [URL]
    let trustedSystemExecutables: Set<URL>

    func firstAvailable(fileManager: FileManager = .default) -> URL? {
        candidates.first { isTrustedExecutable($0, fileManager: fileManager) }
    }

    func isTrustedExecutable(_ candidate: URL, fileManager: FileManager = .default) -> Bool {
        let standardizedCandidate = candidate.standardizedFileURL
        guard candidates.map(\.standardizedFileURL).contains(standardizedCandidate),
              fileManager.isExecutableFile(atPath: standardizedCandidate.path) else {
            return false
        }

        let resolvedCandidate = standardizedCandidate.resolvingSymlinksInPath()
        guard let attributes = try? fileManager.attributesOfItem(atPath: resolvedCandidate.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o022 == 0 else {
            return false
        }

        if trustedSystemExecutables.map(\.standardizedFileURL).contains(standardizedCandidate) {
            return resolvedCandidate == standardizedCandidate
        }

        return trustedRoots.contains { root in
            let standardizedRoot = root.standardizedFileURL
            guard isDescendant(standardizedCandidate, of: standardizedRoot) else { return false }
            return isDescendant(
                resolvedCandidate,
                of: standardizedRoot.resolvingSymlinksInPath()
            )
        }
    }

    private func isDescendant(_ candidate: URL, of directory: URL) -> Bool {
        let directoryPath = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        return candidate.path.hasPrefix(directoryPath)
    }
}

enum TrustedPythonInterpreter {
    static let policy = TrustedPythonInterpreterPolicy(
        candidates: [
            "/opt/homebrew/bin/python3.13",
            "/opt/homebrew/bin/python3.12",
            "/opt/homebrew/bin/python3.11",
            "/opt/homebrew/bin/python3.10",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3.13",
            "/usr/local/bin/python3.12",
            "/usr/local/bin/python3.11",
            "/usr/local/bin/python3.10",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ].map(URL.init(fileURLWithPath:)),
        trustedRoots: [
            URL(fileURLWithPath: "/opt/homebrew", isDirectory: true),
            URL(fileURLWithPath: "/usr/local", isDirectory: true),
        ],
        trustedSystemExecutables: [URL(fileURLWithPath: "/usr/bin/python3")]
    )

    static func firstAvailable(fileManager: FileManager = .default) -> URL? {
        policy.firstAvailable(fileManager: fileManager)
    }
}
