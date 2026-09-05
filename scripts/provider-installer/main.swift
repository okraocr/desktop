import Foundation
import Security

// A private, app-embedded XPC service owns dependency installation. The reader
// and inference workers stay sandboxed; Python wheels must be written outside
// App Sandbox so their native libraries are not quarantined at creation.
@main
enum ProviderInstallerMain {
    static func main() {
        let delegate = ProviderInstallerDelegate()
        let listener = NSXPCListener.service()
        listener.delegate = delegate
        withExtendedLifetime(delegate) { listener.resume() }
    }
}

final class ProviderInstallerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let hostURL = Bundle.main.bundleURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard let host = Bundle(url: hostURL),
              let hostID = host.bundleIdentifier,
              hostID.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil,
              let hostExecutable = host.executableURL,
              connection.effectiveUserIdentifier == getuid(),
              isHost(connection, executable: hostExecutable) else { return false }
        let service = ProviderInstallerService(hostID: hostID)
        connection.exportedInterface = NSXPCInterface(with: ProviderRuntimeXPCProtocol.self)
        connection.exportedObject = service
        connection.invalidationHandler = { service.cancel() }
        connection.interruptionHandler = { service.cancel() }
        connection.resume()
        return true
    }

    private func isHost(_ connection: NSXPCConnection, executable: URL) -> Bool {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: connection.processIdentifier] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code,
              SecCodeCheckValidity(code, [], nil) == errSecSuccess else { return false }
        var information: CFDictionary?
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode,
              SecCodeCopySigningInformation(staticCode, [], &information) == errSecSuccess,
              let information = information as? [String: Any],
              let actual = information[kSecCodeInfoMainExecutable as String] as? URL else { return false }
        return actual.resolvingSymlinksInPath() == executable.resolvingSymlinksInPath()
    }
}

final class ProviderInstallerService: NSObject, ProviderRuntimeXPCProtocol, @unchecked Sendable {
    private let hostID: String
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    init(hostID: String) { self.hostID = hostID }

    func install(providerID: String, withReply reply: @escaping (Int32, String) -> Void) {
        guard let script = ProviderRuntimeServiceConfiguration.scripts[providerID] else {
            reply(1, "Unknown managed provider.")
            return
        }
        lock.lock()
        guard task == nil else {
            lock.unlock()
            reply(1, "A model installation is already running.")
            return
        }
        task = Task { [self] in
            let result: (Int32, String)
            do {
                let root = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Containers/\(hostID)/Data/Library/Application Support/Okra/Providers/\(providerID)")
                // Do not let an app-owned symlink redirect the unsandboxed installer.
                guard root.standardizedFileURL == root.resolvingSymlinksInPath().standardizedFileURL,
                      let resources = Bundle.main.resourceURL,
                      let python = TrustedPythonInterpreter.firstAvailable() else {
                    throw LocalProcessingError.providerUnavailable("A trusted Python interpreter and model installation folder are required.")
                }
                for name in ["venv", "huggingface", "installed-packages.txt", ".ready", "install.lock"] {
                    let destination = root.appendingPathComponent(name)
                    guard destination.standardizedFileURL == destination.resolvingSymlinksInPath().standardizedFileURL else {
                        throw LocalProcessingError.providerUnavailable("Model setup cannot use a redirected installation file.")
                    }
                }
                let gate = LocalExclusiveFileLock(url: root.appendingPathComponent("install.lock"))
                try await gate.acquire()
                defer { gate.release() }
                let output = try await LocalCommandRunner.runAsync(
                    executableURL: URL(fileURLWithPath: "/bin/zsh"),
                    arguments: [resources.appendingPathComponent("ProviderScripts/\(script)").path, root.path, python.path]
                )
                result = (0, output)
            } catch is CancellationError {
                result = (130, "Model installation canceled.")
            } catch {
                result = (1, error.localizedDescription)
            }
            lock.withLock { task = nil }
            reply(result.0, result.1)
        }
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        task?.cancel()
        lock.unlock()
    }
}

// The service compiles the same process runner, cancellation, trusted-interpreter
// policy, and environment as the app, without linking the SwiftUI product.
enum LocalProcessingError: LocalizedError {
    case providerUnavailable(String)
    case commandFailed(command: String, status: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .providerUnavailable(let message): return message
        case .commandFailed(let command, let status, let output):
            return "\(command) exited with status \(status). \(output.suffix(2_000))"
        }
    }
}
