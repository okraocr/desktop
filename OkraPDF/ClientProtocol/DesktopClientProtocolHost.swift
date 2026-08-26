import CryptoKit
import Darwin
import Foundation
import Security

struct DesktopHTTPRequest: Equatable, Sendable {
    let method: String
    let target: String
    let headers: [String: String]
    let body: Data

    var path: String {
        String(target.split(separator: "?", maxSplits: 1).first ?? "")
    }

    var query: [String: String] {
        guard let components = URLComponents(string: "http://127.0.0.1\(target)") else {
            return [:]
        }
        return Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )
    }
}

struct DesktopHTTPResponse: Sendable {
    let status: Int
    let contentType: String
    let body: Data
    let headers: [String: String]

    static func json<T: Encodable>(_ value: T, status: Int = 200) -> Self {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(value)) ?? Data(
            #"{"object":"error","error":"response encoding failed"}"#.utf8
        )
        return DesktopHTTPResponse(
            status: status,
            contentType: "application/json; charset=utf-8",
            body: data,
            headers: [DesktopClientProtocol.header: DesktopClientProtocol.version]
        )
    }

    static func eventStream(_ events: [(type: String, data: Data)]) -> Self {
        let payload = events.enumerated().reduce(into: Data()) { output, entry in
            output.append(Data("id: \(entry.offset)\n".utf8))
            output.append(Data("event: \(entry.element.type)\n".utf8))
            output.append(Data("data: ".utf8))
            output.append(entry.element.data)
            output.append(Data("\n\n".utf8))
        }
        return DesktopHTTPResponse(
            status: 200,
            contentType: "text/event-stream; charset=utf-8",
            body: payload,
            headers: [
                DesktopClientProtocol.header: DesktopClientProtocol.version,
                "cache-control": "no-cache",
                "x-accel-buffering": "no",
            ]
        )
    }
}

@MainActor
final class DesktopClientProtocolRouter {
    private weak var state: AppState?
    private let appVersion: String

    init(state: AppState, appVersion: String? = nil) {
        self.state = state
        self.appVersion = appVersion
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? "dev"
    }

    func route(_ request: DesktopHTTPRequest) -> DesktopHTTPResponse {
        guard let state else {
            return error("The desktop app is shutting down.", status: 503, code: "app_unavailable")
        }

        let components = request.path.split(separator: "/").map(String.init)
        switch (request.method, request.path) {
        case ("GET", "/global/health"):
            return .json(DesktopClientHealth(
                version: appVersion,
                capabilities: [
                    "providers", "parsers", "documents", "parse", "runs.events",
                    "runs.cancel", "runs.resume", "redact", "local_models",
                ]
            ))
        case ("GET", "/global/event"):
            return globalEvents(state: state)
        case ("GET", "/provider"):
            return .json(DesktopClientList(
                object: "client_provider_list",
                data: providerCatalog(state.localProcessing)
            ))
        case ("GET", "/parser"):
            return .json(DesktopClientList(
                object: "client_parser_list",
                data: parserCatalog(state.localProcessing)
            ))
        case ("GET", "/document"):
            return .json(DesktopClientList(
                object: "client_document_list",
                data: state.selectedDocument.flatMap { document(state: state, document: $0) }.map { [$0] } ?? []
            ))
        case ("POST", "/document"):
            return openDocument(request, state: state)
        case ("GET", "/run"):
            return .json(DesktopClientList(
                object: "client_run_list",
                data: state.localProcessing.recentRuns.map { run($0) }
            ))
        default:
            break
        }

        if components.count == 2, components[0] == "document" {
            guard let selected = state.selectedDocument,
                  clientDocumentID(for: selected.filePath) == components[1] else {
                return error("document not found", status: 404, code: "document_not_found")
            }
            if request.method == "GET" {
                return .json(document(state: state, document: selected))
            }
        }

        if components.count == 3,
           components[0] == "document",
           components[2] == "parse",
           request.method == "POST" {
            return startParse(request, documentID: components[1], state: state)
        }

        if components.count >= 2, components[0] == "run" {
            let runID = components[1]
            guard let savedRun = run(withID: runID, coordinator: state.localProcessing) else {
                return error("run not found", status: 404, code: "run_not_found")
            }
            if components.count == 2, request.method == "GET" {
                return .json(run(savedRun))
            }
            if components.count == 3 {
                switch (request.method, components[2]) {
                case ("GET", "events"):
                    return runEvents(savedRun)
                case ("GET", "artifacts"):
                    return artifacts(for: savedRun, coordinator: state.localProcessing)
                case ("POST", "cancel"):
                    guard state.localProcessing.latestRun?.id == runID,
                          state.localProcessing.isRunning else {
                        return error("run is not active", status: 409, code: "run_not_active")
                    }
                    state.localProcessing.cancelRun()
                    return .json(run(state.localProcessing.latestRun ?? savedRun))
                case ("POST", "resume"):
                    guard let document = state.selectedDocument,
                          state.localProcessing.latestRun?.id == runID,
                          state.localProcessing.canResumeLatestRun else {
                        return error("run cannot resume", status: 409, code: "run_not_resumable")
                    }
                    state.localProcessing.resume(document: document)
                    return .json(run(state.localProcessing.latestRun ?? savedRun), status: 202)
                case ("POST", "detect"):
                    return startDetection(runID: runID, state: state)
                case ("GET", "redactions"):
                    return redactions(runID: runID, state: state)
                default:
                    break
                }
            }
        }

        return error("not found", status: 404, code: "not_found")
    }

    private func openDocument(
        _ request: DesktopHTTPRequest,
        state: AppState
    ) -> DesktopHTTPResponse {
        struct Body: Decodable { let source: String?; let path: String? }
        guard let body = try? JSONDecoder().decode(Body.self, from: request.body),
              let path = body.source ?? body.path,
              path.isEmpty == false else {
            return error("source is required", status: 400, code: "invalid_document")
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        state.openPDF(url)
        guard let selected = state.selectedDocument,
              selected.filePath == url.path,
              state.importError == nil else {
            return error(
                state.importError ?? "The app could not open the PDF.",
                status: 403,
                code: "document_access_required",
                nextActions: ["Open the PDF through LaunchServices, then retry the command."]
            )
        }
        return .json(document(state: state, document: selected), status: 201)
    }

    private func startParse(
        _ request: DesktopHTTPRequest,
        documentID: String,
        state: AppState
    ) -> DesktopHTTPResponse {
        struct Body: Decodable {
            let parserId: String?
            let providerId: String?
        }
        guard let selected = state.selectedDocument,
              clientDocumentID(for: selected.filePath) == documentID else {
            return error("document not found", status: 404, code: "document_not_found")
        }
        guard state.localProcessing.isRunning == false,
              state.localProcessing.isInstalling == false,
              state.localProcessing.redaction.isBusy == false else {
            return error("another local operation is active", status: 409, code: "app_busy")
        }
        let body = (try? JSONDecoder().decode(Body.self, from: request.body))
        let requestedID = body?.providerId ?? body?.parserId ?? LocalProviderID.chandraOCR2.rawValue
        guard let providerID = LocalProviderID(rawValue: requestedID),
              state.localProcessing.descriptors.contains(where: { $0.id == providerID }) else {
            return error("parser \(requestedID) is unavailable", status: 400, code: "parser_unavailable")
        }
        state.localProcessing.selectedProviderID = providerID
        guard state.localProcessing.selectedAvailability.isReady else {
            return error(
                state.localProcessing.selectedAvailability.message,
                status: 409,
                code: "parser_not_ready",
                nextActions: ["Open Plugins → Extract in Okra and finish \(state.localProcessing.selectedDescriptor.name) setup."]
            )
        }
        state.parseSelectedDocument()
        guard let started = state.localProcessing.latestRun,
              started.sourcePath == selected.filePath,
              started.status == "running" else {
            return error(
                state.localProcessing.statusMessage,
                status: 409,
                code: "parse_not_started"
            )
        }
        return .json(run(started), status: 202)
    }

    private func startDetection(runID: String, state: AppState) -> DesktopHTTPResponse {
        let redaction = state.localProcessing.redaction
        guard state.localProcessing.latestRun?.id == runID else {
            return error("Open this run in Okra before detecting PII.", status: 409, code: "run_not_selected")
        }
        guard redaction.availability.isReady else {
            return error(
                redaction.availability.message,
                status: 409,
                code: "presidio_not_ready",
                nextActions: ["Open Plugins → Redact in Okra and finish Presidio setup."]
            )
        }
        guard redaction.canDetect else {
            return error(redaction.statusMessage, status: 409, code: "detection_not_ready")
        }
        redaction.detect()
        return .json([
            "object": "client_redaction_status",
            "runId": runID,
            "status": "running",
            "engine": "presidio",
        ], status: 202)
    }

    private func redactions(runID: String, state: AppState) -> DesktopHTTPResponse {
        let redaction = state.localProcessing.redaction
        guard state.localProcessing.latestRun?.id == runID else {
            return error("run is not selected", status: 409, code: "run_not_selected")
        }
        if redaction.isDetecting {
            return .json([
                "object": "client_redaction_status",
                "runId": runID,
                "status": "running",
                "engine": "presidio",
            ], status: 202)
        }
        if let message = redaction.errorMessage {
            return error(message, status: 500, code: "detection_failed")
        }
        guard let detection = redaction.detection else {
            return error("redaction results are not ready", status: 409, code: "redactions_not_ready")
        }
        let result = DesktopClientRedactionDetection(
            runId: detection.runID,
            model: detection.ollamaModel,
            createdAt: DesktopClientDates.string(detection.createdAt),
            candidates: detection.boxes.map { box in
                DesktopClientRedactionCandidate(
                    id: box.id,
                    type: box.type,
                    text: box.text,
                    score: box.score,
                    source: box.source,
                    page: box.page,
                    bbox: clientBox(x: box.x, y: box.y, width: box.width, height: box.height)
                )
            }
        )
        return .json(result)
    }

    private func providerCatalog(_ coordinator: LocalProcessingCoordinator) -> [DesktopClientProvider] {
        coordinator.descriptors.map { descriptor in
            let availability = coordinator.availabilityByProvider[descriptor.id]
                ?? .unavailable("Unavailable")
            let endpoint = descriptor.parserDefinition?.modelDelivery.apiVlmEndpoint
            return DesktopClientProvider(
                id: descriptor.id.rawValue,
                displayName: descriptor.name,
                api: endpoint == nil ? "local" : "openai-chat",
                envKeys: [],
                baseUrl: endpoint?.baseURL,
                defaultModel: descriptor.id == .chandraOCR2 ? descriptor.id.rawValue : nil,
                models: [],
                keyHint: "No API key; execution stays on this Mac.",
                delivery: endpoint == nil ? "on_device" : "loopback",
                ready: availability.isReady,
                status: availability.message,
                isDefault: descriptor.id == .chandraOCR2
            )
        }
    }

    private func parserCatalog(_ coordinator: LocalProcessingCoordinator) -> [DesktopClientParser] {
        coordinator.descriptors.map { descriptor in
            let availability = coordinator.availabilityByProvider[descriptor.id]
                ?? .unavailable("Unavailable")
            let definition = descriptor.parserDefinition
            let version = definition?.modelDelivery.pinnedPackage?.revision
                ?? definition?.outputAdapter.rawValue
                ?? "1"
            return DesktopClientParser(
                id: descriptor.id.rawValue,
                displayName: descriptor.name,
                version: version,
                requires: definition?.runtime == .apiVLM ? "http" : "none",
                defaults: descriptor.id == .chandraOCR2 ? ["engine": "chandra-ocr-2"] : [:],
                ready: availability.isReady,
                status: availability.message,
                isDefault: descriptor.id == .chandraOCR2
            )
        }
    }

    private func document(state: AppState, document: LocalPDFDocument) -> DesktopClientDocument {
        DesktopClientDocument(
            id: clientDocumentID(for: document.filePath),
            title: document.fileName,
            source: document.filePath,
            pageCount: document.totalPages,
            openedAt: DesktopClientDates.string(state.selectedDocumentOpenedAt ?? .now)
        )
    }

    private func run(withID id: String, coordinator: LocalProcessingCoordinator) -> LocalProcessingRun? {
        if coordinator.latestRun?.id == id { return coordinator.latestRun }
        return coordinator.recentRuns.first { $0.id == id }
    }

    private func run(_ savedRun: LocalProcessingRun) -> DesktopClientRun {
        let lifecycles = savedRun.pageLifecycles ?? []
        let pageCount = savedRun.totalPageCount ?? savedRun.pageCount
        let pages = lifecycles.isEmpty
            ? (pageCount > 0 ? (1...pageCount).map { page in
                DesktopClientPageLifecycle(
                    parserId: savedRun.providerId,
                    page: page,
                    state: fallbackPageState(for: savedRun),
                    detail: savedRun.statusMessage,
                    updatedAt: DesktopClientDates.string(savedRun.updatedAt ?? savedRun.startedAt)
                )
            } : [])
            : lifecycles.map { lifecycle in
                DesktopClientPageLifecycle(
                    parserId: lifecycle.parserID,
                    page: lifecycle.pageNumber,
                    state: lifecycle.state == .inProgress ? "in_progress" : lifecycle.state.rawValue,
                    detail: lifecycle.detail,
                    updatedAt: DesktopClientDates.string(lifecycle.updatedAt)
                )
            }
        return DesktopClientRun(
            id: savedRun.id,
            documentId: clientDocumentID(for: savedRun.sourcePath),
            parserId: savedRun.providerId,
            providerId: savedRun.providerId,
            model: savedRun.providerId == LocalProviderID.chandraOCR2.rawValue
                ? LocalProviderID.chandraOCR2.rawValue
                : nil,
            status: clientRunStatus(savedRun.status),
            pageCount: max(pageCount, 0),
            pages: pages,
            createdAt: DesktopClientDates.string(savedRun.startedAt),
            updatedAt: DesktopClientDates.string(
                savedRun.updatedAt ?? savedRun.completedAt ?? savedRun.startedAt
            ),
            error: savedRun.errorMessage
        )
    }

    private func artifacts(
        for savedRun: LocalProcessingRun,
        coordinator: LocalProcessingCoordinator
    ) -> DesktopHTTPResponse {
        guard let artifacts = clientArtifacts(for: savedRun, coordinator: coordinator) else {
            return error("run artifacts are not ready", status: 409, code: "artifacts_not_ready")
        }
        return .json(artifacts)
    }

    private func clientArtifacts(
        for savedRun: LocalProcessingRun,
        coordinator: LocalProcessingCoordinator
    ) -> DesktopClientArtifacts? {
        guard savedRun.status == "succeeded",
              let outputPath = savedRun.outputPath,
              let markdown = try? String(contentsOfFile: outputPath, encoding: .utf8) else {
            return nil
        }
        let structured: StructuredExtractionDocument?
        if coordinator.latestRun?.id == savedRun.id {
            structured = coordinator.structuredOutput
        } else if let path = savedRun.structuredOutputPath {
            structured = try? StructuredExtractionDocument.load(from: URL(fileURLWithPath: path))
        } else {
            structured = nil
        }
        let blocks = structured?.pages.flatMap { page in
            page.blocks.compactMap { block -> DesktopClientBlock? in
                guard let bbox = block.bbox,
                      bbox.unit == "normalized",
                      bbox.origin == "top-left",
                      block.displayText.isEmpty == false else { return nil }
                return DesktopClientBlock(
                    label: block.type.isEmpty ? "Text" : block.type,
                    bbox: clientBox(
                        x: bbox.x,
                        y: bbox.y,
                        width: bbox.width,
                        height: bbox.height
                    ),
                    text: block.displayText,
                    page: page.pageNumber
                )
            }
        } ?? []
        var warnings = structured?.pages.flatMap(\.diagnostics.warnings) ?? []
        let ungrounded = structured?.pages.reduce(0) {
            $0 + ($1.diagnostics.ungroundedBlockCount ?? 0)
        } ?? 0
        if ungrounded > 0 {
            warnings.append("\(ungrounded) structured blocks have no source coordinates and are omitted from blocks.json.")
        }
        let duration = (savedRun.completedAt ?? .now).timeIntervalSince(savedRun.startedAt) * 1_000
        return DesktopClientArtifacts(
            markdown: markdown,
            blocks: blocks,
            manifest: DesktopClientManifest(
                parserId: savedRun.providerId,
                providerId: savedRun.providerId,
                model: savedRun.providerId == LocalProviderID.chandraOCR2.rawValue
                    ? LocalProviderID.chandraOCR2.rawValue
                    : nil,
                pageCount: savedRun.pageCount,
                durationMs: max(duration, 0),
                warnings: warnings
            )
        )
    }

    private func globalEvents(state: AppState) -> DesktopHTTPResponse {
        var sequence = 0
        let connected = DesktopServerConnectedEvent(
            protocol: DesktopClientProtocol.version,
            id: "evt_connected",
            seq: sequence,
            createdAt: DesktopClientDates.string(.now),
            type: "server.connected",
            host: "desktop_loopback"
        )
        var events: [(type: String, data: Data)] = [
            (connected.type, (try? encoded(connected)) ?? Data()),
        ]
        if let selected = state.selectedDocument {
            sequence += 1
            let opened = DesktopDocumentOpenedEvent(
                protocol: DesktopClientProtocol.version,
                id: "evt_document_\(clientDocumentID(for: selected.filePath))",
                seq: sequence,
                createdAt: DesktopClientDates.string(state.selectedDocumentOpenedAt ?? .now),
                type: "document.opened",
                document: document(state: state, document: selected)
            )
            events.append((opened.type, (try? encoded(opened)) ?? Data()))
        }
        return .eventStream(events)
    }

    private func runEvents(_ savedRun: LocalProcessingRun) -> DesktopHTTPResponse {
        let snapshot = run(savedRun)
        let sequence = savedRun.eventSequence ?? 0
        let createdAt = DesktopClientDates.string(savedRun.updatedAt ?? .now)
        let event: (type: String, data: Data)
        switch snapshot.status {
        case "succeeded":
            guard let state,
                  let artifacts = clientArtifacts(
                    for: savedRun,
                    coordinator: state.localProcessing
                  ) else {
                return error("run artifacts are not ready", status: 409, code: "artifacts_not_ready")
            }
            let completed = DesktopRunCompletedEvent(
                protocol: DesktopClientProtocol.version,
                id: "evt_\(savedRun.id)_\(sequence)",
                seq: sequence,
                createdAt: createdAt,
                type: "run.completed",
                run: snapshot,
                artifacts: artifacts
            )
            event = (completed.type, (try? encoded(completed)) ?? Data())
        case "failed":
            let failed = DesktopRunFailedEvent(
                protocol: DesktopClientProtocol.version,
                id: "evt_\(savedRun.id)_\(sequence)",
                seq: sequence,
                createdAt: createdAt,
                type: "run.failed",
                runId: savedRun.id,
                message: savedRun.errorMessage ?? "The local parse failed."
            )
            event = (failed.type, (try? encoded(failed)) ?? Data())
        case "cancelled":
            let cancelled = DesktopRunCancelledEvent(
                protocol: DesktopClientProtocol.version,
                id: "evt_\(savedRun.id)_\(sequence)",
                seq: sequence,
                createdAt: createdAt,
                type: "run.cancelled",
                runId: savedRun.id
            )
            event = (cancelled.type, (try? encoded(cancelled)) ?? Data())
        default:
            let started = DesktopRunStartedEvent(
                protocol: DesktopClientProtocol.version,
                id: "evt_\(savedRun.id)_\(sequence)",
                seq: sequence,
                createdAt: createdAt,
                type: "run.started",
                run: snapshot
            )
            event = (started.type, (try? encoded(started)) ?? Data())
        }
        return .eventStream([event])
    }

    private func error(
        _ message: String,
        status: Int,
        code: String,
        nextActions: [String]? = nil
    ) -> DesktopHTTPResponse {
        .json(
            DesktopClientError(
                error: message,
                code: code,
                nextActions: nextActions
            ),
            status: status
        )
    }

    private func clientDocumentID(for path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        return "doc_" + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private func clientBox(x: Double, y: Double, width: Double, height: Double) -> [Double] {
        let x1 = min(max(x, 0), 1) * 1_000
        let y1 = min(max(y, 0), 1) * 1_000
        let x2 = min(max(x + width, 0), 1) * 1_000
        let y2 = min(max(y + height, 0), 1) * 1_000
        return [x1, y1, max(x1, x2), max(y1, y2)]
    }

    private func clientRunStatus(_ status: String) -> String {
        switch status {
        case "canceling": return "cancelling"
        case "canceled", "cancelled": return "cancelled"
        case "interrupted": return "attention"
        case "running", "succeeded", "failed", "queued", "attention": return status
        default: return "attention"
        }
    }

    private func fallbackPageState(for run: LocalProcessingRun) -> String {
        switch clientRunStatus(run.status) {
        case "running", "cancelling": return "in_progress"
        case "succeeded": return "done"
        case "failed": return "error"
        case "attention", "cancelled": return "attention"
        default: return "idle"
        }
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

}

private struct DesktopServerConnectedEvent: Encodable {
    let `protocol`: String
    let id: String
    let seq: Int
    let createdAt: String
    let type: String
    let host: String
}

private struct DesktopDocumentOpenedEvent: Encodable {
    let `protocol`: String
    let id: String
    let seq: Int
    let createdAt: String
    let type: String
    let document: DesktopClientDocument
}

private struct DesktopRunStartedEvent: Encodable {
    let `protocol`: String
    let id: String
    let seq: Int
    let createdAt: String
    let type: String
    let run: DesktopClientRun
}

private struct DesktopRunCompletedEvent: Encodable {
    let `protocol`: String
    let id: String
    let seq: Int
    let createdAt: String
    let type: String
    let run: DesktopClientRun
    let artifacts: DesktopClientArtifacts
}

private struct DesktopRunFailedEvent: Encodable {
    let `protocol`: String
    let id: String
    let seq: Int
    let createdAt: String
    let type: String
    let runId: String
    let message: String
}

private struct DesktopRunCancelledEvent: Encodable {
    let `protocol`: String
    let id: String
    let seq: Int
    let createdAt: String
    let type: String
    let runId: String
}

final class DesktopClientProtocolHost {
    private static let maximumRequestBytes = 1_048_576
    private let router: DesktopClientProtocolRouter
    private let endpointStateURL: URL?
    private let queue = DispatchQueue(label: "com.okrapdf.desktop.client-protocol")
    private var listeningSocket: Int32 = -1
    private var source: DispatchSourceRead?
    private(set) var endpointState: DesktopClientEndpointState?

    init(
        router: DesktopClientProtocolRouter,
        endpointStateURL: URL? = DesktopClientProtocolPaths.endpointStateURL
    ) {
        self.router = router
        self.endpointStateURL = endpointStateURL
    }

    deinit {
        stop()
    }

    func start() throws {
        guard listeningSocket == -1 else { return }
        let socketFD = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw DesktopClientHostError.socketCreation(errno) }

        var noSignal: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(socketFD, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(socketFD)
            throw DesktopClientHostError.bind(errno)
        }
        guard Darwin.listen(socketFD, 16) == 0 else {
            Darwin.close(socketFD)
            throw DesktopClientHostError.listen(errno)
        }

        var boundAddress = sockaddr_in()
        var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(socketFD, socketAddress, &boundLength)
            }
        }
        guard nameResult == 0 else {
            Darwin.close(socketFD)
            throw DesktopClientHostError.endpoint(errno)
        }

        listeningSocket = socketFD
        let state = DesktopClientEndpointState(
            protocolVersion: DesktopClientProtocol.version,
            pid: getpid(),
            port: UInt16(bigEndian: boundAddress.sin_port),
            token: try secureToken(),
            startedAt: DesktopClientDates.string(.now)
        )
        if let endpointStateURL {
            try writeEndpointState(state, to: endpointStateURL)
        }
        endpointState = state

        let source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptConnections() }
        source.setCancelHandler { Darwin.close(socketFD) }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        listeningSocket = -1
        if let endpointStateURL,
           let onDisk = try? JSONDecoder().decode(
            DesktopClientEndpointState.self,
            from: Data(contentsOf: endpointStateURL)
        ), onDisk.pid == getpid() {
            try? FileManager.default.removeItem(at: endpointStateURL)
        }
        endpointState = nil
    }

    private func acceptConnections() {
        guard listeningSocket >= 0 else { return }
        while true {
            let client = Darwin.accept(listeningSocket, nil, nil)
            if client < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                return
            }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handle(client)
            }
            return
        }
    }

    private func handle(_ client: Int32) {
        defer { Darwin.close(client) }
        var noSignal: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        guard let request = readRequest(client) else {
            send(.json(DesktopClientError(error: "invalid request", code: "invalid_request", nextActions: nil), status: 400), to: client)
            return
        }
        guard let token = endpointState?.token,
              request.headers["authorization"] == "Bearer \(token)" else {
            send(.json(DesktopClientError(error: "unauthorized", code: "unauthorized", nextActions: nil), status: 401), to: client)
            return
        }

        let semaphore = DispatchSemaphore(value: 0)
        var response: DesktopHTTPResponse?
        Task { @MainActor [router] in
            response = router.route(request)
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 30) == .success, let response else {
            send(.json(DesktopClientError(error: "request timed out", code: "timeout", nextActions: nil), status: 504), to: client)
            return
        }
        send(response, to: client)
    }

    private func readRequest(_ socket: Int32) -> DesktopHTTPRequest? {
        var data = Data()
        var headerEnd: Range<Data.Index>?
        while data.count <= Self.maximumRequestBytes {
            var buffer = [UInt8](repeating: 0, count: 8_192)
            let count = Darwin.recv(socket, &buffer, buffer.count, 0)
            guard count > 0 else { return nil }
            data.append(buffer, count: count)
            headerEnd = data.range(of: Data("\r\n\r\n".utf8))
            if headerEnd != nil { break }
        }
        guard let headerEnd,
              let headerText = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else {
            return nil
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count == 3 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        guard contentLength >= 0,
              contentLength <= Self.maximumRequestBytes else { return nil }
        let bodyStart = headerEnd.upperBound
        while data.count - bodyStart < contentLength {
            var buffer = [UInt8](repeating: 0, count: min(8_192, contentLength - (data.count - bodyStart)))
            let count = Darwin.recv(socket, &buffer, buffer.count, 0)
            guard count > 0 else { return nil }
            data.append(buffer, count: count)
        }
        return DesktopHTTPRequest(
            method: String(requestParts[0]),
            target: String(requestParts[1]),
            headers: headers,
            body: Data(data[bodyStart..<(bodyStart + contentLength)])
        )
    }

    private func send(_ response: DesktopHTTPResponse, to socket: Int32) {
        var headers = response.headers
        headers["content-type"] = response.contentType
        headers["content-length"] = String(response.body.count)
        headers["connection"] = "close"
        let headerLines = headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        var data = Data("HTTP/1.1 \(response.status) \(reason(response.status))\r\n".utf8)
        data.append(Data((headerLines.joined(separator: "\r\n") + "\r\n\r\n").utf8))
        data.append(response.body)
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var sent = 0
            while sent < buffer.count {
                let count = Darwin.send(socket, base.advanced(by: sent), buffer.count - sent, 0)
                if count <= 0 { return }
                sent += count
            }
        }
    }

    private func writeEndpointState(
        _ state: DesktopClientEndpointState,
        to endpointStateURL: URL
    ) throws {
        let directory = endpointStateURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: endpointStateURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: endpointStateURL.path
        )
    }

    private func secureToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw DesktopClientHostError.randomToken
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 201: "Created"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 409: "Conflict"
        case 415: "Unsupported Media Type"
        case 500: "Internal Server Error"
        case 503: "Service Unavailable"
        case 504: "Gateway Timeout"
        default: "Error"
        }
    }
}

enum DesktopClientHostError: LocalizedError {
    case socketCreation(Int32)
    case bind(Int32)
    case listen(Int32)
    case endpoint(Int32)
    case randomToken

    var errorDescription: String? {
        switch self {
        case .socketCreation(let code): "Could not create the local CLI socket (errno \(code))."
        case .bind(let code): "Could not bind the local CLI socket to loopback (errno \(code))."
        case .listen(let code): "Could not listen for local CLI requests (errno \(code))."
        case .endpoint(let code): "Could not resolve the local CLI endpoint (errno \(code))."
        case .randomToken: "Could not create the local CLI authentication token."
        }
    }
}
