import Foundation

enum LocalProcessingError: LocalizedError {
    case providerUnavailable(String)
    case missingResource(String)
    case commandFailed(command: String, status: Int32, output: String)
    var errorDescription: String? {
        switch self {
        case .providerUnavailable(let value), .missingResource(let value): return value
        case .commandFailed(_, _, let output): return output
        }
    }
}

@main
enum InstallationProbe {
    static func main() {
        Task {
            do {
                let root = LocalProviderPaths.unlimitedOCRRoot
                let stallRoot = LocalProviderPaths.dotsOCRRoot
                defer {
                    try? FileManager.default.removeItem(at: root)
                    try? FileManager.default.removeItem(at: stallRoot)
                }
                let resources = Bundle.main.resourceURL!.appendingPathComponent("ProviderScripts")
                let python = URL(fileURLWithPath: CommandLine.arguments[1])
                let connection = NSXPCConnection(serviceName: ProviderRuntimeServiceConfiguration.identifier)
                connection.remoteObjectInterface = NSXPCInterface(with: ProviderRuntimeXPCProtocol.self)
                connection.resume()
                let rejected: Int32 = await withCheckedContinuation { continuation in
                    (connection.remoteObjectProxy as! ProviderRuntimeXPCProtocol)
                        .install(providerID: "../../outside") { status, _ in continuation.resume(returning: status) }
                }
                connection.invalidate()
                guard rejected != 0 else {
                    throw LocalProcessingError.providerUnavailable("Installer accepted an unknown provider")
                }
                for _ in 0..<2 {
                    try await ProviderRuntimeInstaller.run(
                        scriptURL: resources.appendingPathComponent("install-unlimited-ocr.sh"),
                        rootURL: root, pythonURL: python
                    )
                    _ = try await LocalCommandRunner.runAsync(
                        executableURL: root.appendingPathComponent("venv/bin/python"),
                        arguments: ["-c", """
                            import ctypes, mimetypes, sys
                            assert mimetypes.guess_type('document.pdf')[0] == 'application/pdf'
                            library = ctypes.CDLL(sys.argv[1])
                            assert library.provider_probe() == 42
                            """, root.appendingPathComponent("venv/provider-probe.dylib").path]
                    )
                }
                let install = Task {
                    try await ProviderRuntimeInstaller.run(
                        scriptURL: resources.appendingPathComponent("install-dots-ocr.sh"),
                        rootURL: stallRoot, pythonURL: python
                    )
                }
                let heartbeat = stallRoot.appendingPathComponent("heartbeat")
                for _ in 0..<100 {
                    if FileManager.default.fileExists(atPath: heartbeat.path) { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                guard FileManager.default.fileExists(atPath: heartbeat.path) else {
                    throw LocalProcessingError.providerUnavailable("Cancel probe never started")
                }
                install.cancel()
                do {
                    try await install.value
                    throw LocalProcessingError.providerUnavailable("Canceled installation succeeded")
                } catch is CancellationError {}
                try await Task.sleep(for: .milliseconds(1_500))
                let stopped = try Data(contentsOf: heartbeat)
                try await Task.sleep(for: .milliseconds(200))
                guard try Data(contentsOf: heartbeat) == stopped else {
                    throw LocalProcessingError.providerUnavailable("Canceled installer left a running child")
                }
                print("XPC install, native library load, retry, and cancellation passed")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("\(error)\n".utf8))
                exit(1)
            }
        }
        dispatchMain()
    }
}
