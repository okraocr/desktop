import Foundation

enum ProviderRuntimeInstaller {
    static func run(scriptURL: URL, rootURL: URL, pythonURL: URL) async throws {
        // SwiftPM builds and hermetic installer tests are not sandboxed apps.
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            _ = try await LocalCommandRunner.runAsync(
                executableURL: URL(fileURLWithPath: "/bin/zsh"),
                arguments: [scriptURL.path, rootURL.path, pythonURL.path]
            )
            return
        }
        let providerID = rootURL.lastPathComponent
        guard ProviderRuntimeServiceConfiguration.scripts[providerID] == scriptURL.lastPathComponent,
              rootURL.standardizedFileURL == LocalProviderPaths.providersRoot
                .appendingPathComponent(providerID, isDirectory: true).standardizedFileURL else {
            throw LocalProcessingError.providerUnavailable("The model installation location is invalid.")
        }
        let serviceURL = Bundle.main.bundleURL.appendingPathComponent(
            "Contents/XPCServices/\(ProviderRuntimeServiceConfiguration.identifier).xpc"
        )
        guard FileManager.default.fileExists(atPath: serviceURL.path) else {
            throw LocalProcessingError.missingResource("model installation service")
        }
        try await ProviderRuntimeInstallation(providerID: providerID).run()
    }
}

private final class ProviderRuntimeInstallation: @unchecked Sendable {
    private let providerID: String
    private let connection = NSXPCConnection(serviceName: ProviderRuntimeServiceConfiguration.identifier)
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var cancelled = false

    init(providerID: String) {
        self.providerID = providerID
        connection.remoteObjectInterface = NSXPCInterface(with: ProviderRuntimeXPCProtocol.self)
    }

    func run() async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                let alreadyCancelled = cancelled
                lock.unlock()
                guard !alreadyCancelled else {
                    finish(CancellationError())
                    return
                }
                connection.interruptionHandler = { [weak self] in self?.connectionFailed() }
                connection.invalidationHandler = { [weak self] in self?.connectionFailed() }
                connection.resume()
                guard let service = connection.remoteObjectProxyWithErrorHandler({ [weak self] _ in
                    self?.connectionFailed()
                }) as? ProviderRuntimeXPCProtocol else {
                    connectionFailed()
                    return
                }
                service.install(providerID: providerID) { [self] status, output in
                    finish(status == 0 ? nil : LocalProcessingError.commandFailed(
                        command: "Model setup", status: status, output: output
                    ))
                }
                lock.lock()
                let shouldCancel = cancelled
                lock.unlock()
                if shouldCancel { service.cancel() }
            }
        } onCancel: {
            self.lock.lock()
            self.cancelled = true
            let started = self.continuation != nil
            self.lock.unlock()
            if started {
                (self.connection.remoteObjectProxy as? ProviderRuntimeXPCProtocol)?.cancel()
            }
        }
    }

    private func connectionFailed() {
        finish(LocalProcessingError.providerUnavailable(
            "The model installation service stopped. Retry setup."
        ))
    }

    private func finish(_ error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let resultError: Error? = cancelled ? CancellationError() : error
        lock.unlock()
        guard let continuation else { return }
        connection.invalidate()
        if let resultError {
            continuation.resume(throwing: resultError)
        } else {
            continuation.resume()
        }
    }
}
