import Foundation

enum LocalProcessEnvironment {
    static let fixedPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    private static let allowedAdditionKeys: Set<String> = [
        "HF_DATASETS_OFFLINE",
        "HF_HOME",
        "HF_HUB_OFFLINE",
        "OLLAMA_HOST",
        "PYTHONDONTWRITEBYTECODE",
        "TRANSFORMERS_OFFLINE",
    ]

    static func make(
        parent: [String: String] = ProcessInfo.processInfo.environment,
        additions: [String: String] = [:],
        fileManager: FileManager = .default
    ) throws -> [String: String] {
        let rejectedKeys = Set(additions.keys).subtracting(allowedAdditionKeys)
        guard rejectedKeys.isEmpty else {
            throw LocalProcessEnvironmentError.disallowedVariables(rejectedKeys.sorted())
        }

        var environment = [
            "HOME": fileManager.homeDirectoryForCurrentUser.path,
            "PATH": fixedPath,
            "TMPDIR": fileManager.temporaryDirectory.path,
        ]
        for key in ["LANG", "LC_ALL", "LC_CTYPE"] {
            if let value = parent[key], isSafeLocale(value) {
                environment[key] = value
            }
        }
        environment.merge(additions) { _, addition in addition }
        return environment
    }

    private static func isSafeLocale(_ value: String) -> Bool {
        guard value.isEmpty == false, value.count <= 64 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.@-"))
        return value.rangeOfCharacter(from: allowed.inverted) == nil
    }
}

enum LocalProcessEnvironmentError: LocalizedError {
    case disallowedVariables([String])

    var errorDescription: String? {
        switch self {
        case .disallowedVariables(let keys):
            return "Provider process environment contains unsupported variables: \(keys.joined(separator: ", "))."
        }
    }
}
