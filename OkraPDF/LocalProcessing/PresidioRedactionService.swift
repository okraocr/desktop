import Darwin
import Foundation

protocol PresidioRedactionServicing: AnyObject {
    func availability() async -> LocalProviderAvailability
    func install(
        progress: @escaping @Sendable (LocalProviderSetupProgress) -> Void
    ) async throws
    func detect(
        runID: String,
        document: StructuredExtractionDocument,
        ollamaModel: String?,
        redactionsURL: URL
    ) async throws -> RedactionDetection
    func shutdown() async
}

actor PresidioRedactionService: PresidioRedactionServicing {
    private let rootURL: URL
    private let externalBaseURL: URL?
    private let simulation: Bool
    private var worker: PresidioWorkerProcess?

    init(
        rootURL: URL = LocalProviderPaths.providersRoot
            .appendingPathComponent("presidio", isDirectory: true),
        externalURL: String? = ProcessInfo.processInfo.environment["OKRA_PRESIDIO_URL"],
        simulation: Bool = ProcessInfo.processInfo.environment["OKRA_DESKTOP_SIMULATE_PRESIDIO"] == "1"
    ) {
        self.rootURL = rootURL
        self.externalBaseURL = try? Self.loopbackURL(from: externalURL)
        self.simulation = simulation
    }

    deinit {
        worker?.stop()
    }

    func availability() async -> LocalProviderAvailability {
        if let externalBaseURL {
            var request = URLRequest(
                url: externalBaseURL.appendingPathComponent("health"),
                timeoutInterval: 1.5
            )
            request.httpMethod = "GET"
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    return .unavailable("Presidio is not reachable on loopback.")
                }
                return .ready
            } catch {
                return .unavailable("Presidio is not reachable on loopback.")
            }
        }
        if ProcessInfo.processInfo.environment["OKRA_PRESIDIO_URL"] != nil {
            return .unavailable("Presidio must use an HTTP loopback URL.")
        }
        if simulation {
            return Self.systemPythonURL() == nil
                ? .unavailable("Python 3.10+ is required for Presidio simulation.")
                : .simulated("Presidio simulation ready")
        }
        guard FileManager.default.isExecutableFile(atPath: pythonURL.path),
              PresidioReadyMarker.read(from: readyMarkerURL)?.matchesCurrentRuntime == true else {
            return .setupRequired("Microsoft Presidio 2.2.364 + English spaCy model")
        }
        return .ready
    }

    func install(
        progress: @escaping @Sendable (LocalProviderSetupProgress) -> Void
    ) async throws {
        guard externalBaseURL == nil else {
            throw PresidioRedactionError.externalSetupDisabled
        }
        guard simulation == false else { return }
        progress(
            LocalProviderSetupProgress(
                phase: .preparing,
                fraction: nil,
                message: "Preparing the Presidio plugin…"
            )
        )
        guard let scriptURL = ProviderResources.scriptURL(
            named: "install-presidio",
            extension: "sh"
        ) else {
            throw LocalProcessingError.missingResource("Presidio installer")
        }
        worker?.stop()
        worker = nil
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        progress(
            LocalProviderSetupProgress(
                phase: .installingRuntime,
                fraction: nil,
                message: "Installing Microsoft Presidio 2.2.364 and the English spaCy model…"
            )
        )
        _ = try await LocalCommandRunner.runAsync(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: [scriptURL.path, rootURL.path]
        )
        try Task.checkCancellation()
        progress(
            LocalProviderSetupProgress(
                phase: .verifying,
                fraction: 0.95,
                message: "Verifying the pinned Presidio runtime…"
            )
        )
        guard PresidioReadyMarker.read(from: readyMarkerURL)?.matchesCurrentRuntime == true else {
            throw PresidioRedactionError.setupVerificationFailed
        }
        progress(
            LocalProviderSetupProgress(
                phase: .ready,
                fraction: 1,
                message: "Microsoft Presidio is ready locally."
            )
        )
    }

    func detect(
        runID: String,
        document: StructuredExtractionDocument,
        ollamaModel: String?,
        redactionsURL: URL
    ) async throws -> RedactionDetection {
        let trimmedModel = ollamaModel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = trimmedModel?.isEmpty == false ? trimmedModel : nil
        let baseURL: URL
        if let externalBaseURL {
            guard model == nil else { throw PresidioRedactionError.externalOllamaConfiguration }
            baseURL = externalBaseURL
        } else {
            guard (await availability()).isReady else {
                throw PresidioRedactionError.setupRequired
            }
            baseURL = try await managedWorkerBaseURL()
        }

        var boxes: [RedactionBox] = []
        for page in document.pages.sorted(by: { $0.pageNumber < $1.pageNumber }) {
            for block in page.blocks {
                try Task.checkCancellation()
                guard let bbox = block.bbox,
                      let normalized = bbox.clippedNormalizedRect,
                      block.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                    continue
                }
                let findings = try await analyze(
                    text: String(block.displayText.prefix(400_000)),
                    ollamaModel: model,
                    baseURL: baseURL
                )
                for finding in findings where finding.end > finding.start {
                    let text = finding.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let identifier = [
                        "redaction",
                        String(page.pageNumber),
                        block.id,
                        finding.entityType,
                        String(finding.start),
                        String(finding.end),
                    ].joined(separator: "-")
                    boxes.append(
                        RedactionBox(
                            id: identifier,
                            page: page.pageNumber,
                            x: Double(normalized.minX),
                            y: Double(normalized.minY),
                            width: Double(normalized.width),
                            height: Double(normalized.height),
                            type: finding.entityType,
                            text: text,
                            score: min(max(finding.score, 0), 1),
                            source: model == nil ? "presidio" : "presidio+ollama",
                            blockID: block.id
                        )
                    )
                }
            }
        }
        boxes.sort {
            ($0.page, $0.y, $0.x, $0.type, $0.id)
                < ($1.page, $1.y, $1.x, $1.type, $1.id)
        }
        let detection = RedactionDetection.make(
            runID: runID,
            ollamaModel: model,
            boxes: boxes
        )
        try detection.write(to: redactionsURL)
        return detection
    }

    func shutdown() async {
        worker?.stop()
        worker = nil
    }

    private var pythonURL: URL {
        rootURL
            .appendingPathComponent("venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python")
    }

    private var readyMarkerURL: URL {
        rootURL.appendingPathComponent(".ready")
    }

    private var workerScriptURL: URL {
        rootURL.appendingPathComponent("presidio-worker.py")
    }

    private func managedWorkerBaseURL() async throws -> URL {
        if let worker, worker.process.isRunning {
            return worker.baseURL
        }
        worker?.stop()
        worker = nil

        guard let bundledWorker = ProviderResources.scriptURL(
            named: "presidio-worker",
            extension: "py"
        ) else {
            throw LocalProcessingError.missingResource("Presidio worker")
        }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data(contentsOf: bundledWorker).write(to: workerScriptURL, options: .atomic)

        let executable = simulation ? Self.systemPythonURL() : pythonURL
        guard let executable else { throw PresidioRedactionError.pythonUnavailable }
        let started = try PresidioWorkerProcess.start(
            pythonURL: executable,
            scriptURL: workerScriptURL,
            simulation: simulation
        )
        worker = started
        try await waitUntilReady(started)
        return started.baseURL
    }

    private func waitUntilReady(_ worker: PresidioWorkerProcess) async throws {
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            try Task.checkCancellation()
            guard worker.process.isRunning else {
                throw PresidioRedactionError.workerExited
            }
            var request = URLRequest(
                url: worker.baseURL.appendingPathComponent("health"),
                timeoutInterval: 2
            )
            request.httpMethod = "GET"
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse,
               http.statusCode == 200,
               let health = try? JSONDecoder().decode(PresidioHealth.self, from: data) {
                if let loadError = health.loadError, loadError.isEmpty == false {
                    throw PresidioRedactionError.workerLoadFailed(loadError)
                }
                if health.loaded { return }
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw PresidioRedactionError.workerTimedOut
    }

    private func analyze(
        text: String,
        ollamaModel: String?,
        baseURL: URL
    ) async throws -> [PresidioFinding] {
        let payload = PresidioAnalyzePayload(
            text: text,
            language: "en",
            scoreThreshold: 0.5,
            ollamaModel: ollamaModel
        )
        var request = URLRequest(
            url: baseURL.appendingPathComponent("analyze"),
            timeoutInterval: ollamaModel == nil ? 60 : 300
        )
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PresidioRedactionError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let serverError = try? JSONDecoder().decode(PresidioServerError.self, from: data)
            throw PresidioRedactionError.server(
                serverError?.error ?? "Presidio returned status \(http.statusCode)."
            )
        }
        return try JSONDecoder().decode([PresidioFinding].self, from: data)
    }

    private static func systemPythonURL() -> URL? {
        [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        .map(URL.init(fileURLWithPath:))
        .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func loopbackURL(from value: String?) throws -> URL? {
        guard let value, value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        guard var components = URLComponents(string: value),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host?.lowercased(),
              ["127.0.0.1", "localhost", "::1"].contains(host) else {
            throw PresidioRedactionError.nonLoopbackURL
        }
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw PresidioRedactionError.nonLoopbackURL }
        return url
    }
}

private final class PresidioWorkerProcess {
    let process: Process
    let baseURL: URL
    private let outputPipe: Pipe

    private init(process: Process, baseURL: URL, outputPipe: Pipe) {
        self.process = process
        self.baseURL = baseURL
        self.outputPipe = outputPipe
    }

    static func start(
        pythonURL: URL,
        scriptURL: URL,
        simulation: Bool
    ) throws -> PresidioWorkerProcess {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = pythonURL
        process.arguments = [scriptURL.path, "serve", "--host", "127.0.0.1", "--port", "0"]
            + (simulation ? ["--simulate"] : [])
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["OLLAMA_HOST"] = "http://127.0.0.1:11434"
        process.environment = environment
        try process.run()

        do {
            let line = try readLine(from: outputPipe.fileHandleForReading, process: process)
            let announcement = try JSONDecoder().decode(
                PresidioPortAnnouncement.self,
                from: Data(line.utf8)
            )
            guard announcement.port > 0,
                  let baseURL = URL(string: "http://127.0.0.1:\(announcement.port)") else {
                throw PresidioRedactionError.invalidWorkerAnnouncement
            }
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                if handle.availableData.isEmpty {
                    handle.readabilityHandler = nil
                }
            }
            return PresidioWorkerProcess(
                process: process,
                baseURL: baseURL,
                outputPipe: outputPipe
            )
        } catch {
            process.terminate()
            process.waitUntilExit()
            throw error
        }
    }

    func stop() {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }

    private static func readLine(from handle: FileHandle, process: Process) throws -> String {
        var data = Data()
        while process.isRunning, data.count < 16_384 {
            guard let byte = try handle.read(upToCount: 1), byte.isEmpty == false else { break }
            if byte[byte.startIndex] == 0x0A { break }
            data.append(byte)
        }
        guard let line = String(data: data, encoding: .utf8), line.isEmpty == false else {
            throw PresidioRedactionError.invalidWorkerAnnouncement
        }
        return line
    }
}

private struct PresidioPortAnnouncement: Decodable {
    let port: Int
}

private struct PresidioHealth: Decodable {
    let loaded: Bool
    let loadError: String?
}

private struct PresidioServerError: Decodable {
    let error: String
}

enum PresidioRedactionError: LocalizedError {
    case externalSetupDisabled
    case externalOllamaConfiguration
    case invalidResponse
    case invalidWorkerAnnouncement
    case nonLoopbackURL
    case pythonUnavailable
    case server(String)
    case setupRequired
    case setupVerificationFailed
    case workerExited
    case workerLoadFailed(String)
    case workerTimedOut

    var errorDescription: String? {
        switch self {
        case .externalSetupDisabled:
            return "Managed setup is disabled while OKRA_PRESIDIO_URL is configured."
        case .externalOllamaConfiguration:
            return "An external Presidio service owns its recognizer configuration."
        case .invalidResponse:
            return "Presidio returned an invalid response."
        case .invalidWorkerAnnouncement:
            return "The local Presidio worker did not announce a valid loopback port."
        case .nonLoopbackURL:
            return "Presidio must use an HTTP loopback URL."
        case .pythonUnavailable:
            return "Python 3.10 or later is required for Presidio."
        case .server(let message):
            return message
        case .setupRequired:
            return "Set up Microsoft Presidio locally before detecting PII."
        case .setupVerificationFailed:
            return "Presidio setup finished without a valid ready marker."
        case .workerExited:
            return "The local Presidio worker exited before it was ready."
        case .workerLoadFailed(let message):
            return "Presidio could not load: \(message)"
        case .workerTimedOut:
            return "Presidio did not finish loading in time."
        }
    }
}
