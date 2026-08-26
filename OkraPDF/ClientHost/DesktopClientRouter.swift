import Foundation
import OkraClientCore

@MainActor
final class DesktopClientRouter {
    private weak var appState: AppState?
    private var openedAtByDocumentID: [String: Date] = [:]

    init(appState: AppState) {
        self.appState = appState
    }

    func route(_ request: DesktopHTTPRequest) async -> DesktopHTTPResponse {
        guard let appState else {
            return .failure(status: 503, code: "app_unavailable", message: "Okra.app is shutting down.")
        }
        let path = request.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? request.path
        let segments = path.split(separator: "/").map(String.init)

        if request.method == "GET", path == "/global/health" {
            return .json(ClientHealth(version: appVersion, capabilities: [
                "providers", "parsers", "documents", "parse", "runs.events",
                "runs.cancel", "runs.resume", "redact", "local_models",
            ]))
        }
        if request.method == "GET", path == "/provider" {
            let coordinator = appState.localProcessing
            return .json(coordinator.descriptors.map { descriptor in
                DesktopClientProjection.provider(
                    descriptor,
                    availability: coordinator.availability(for: descriptor.id),
                    selected: coordinator.selectedProviderID == descriptor.id
                )
            })
        }
        if request.method == "GET", path == "/parser" {
            return .json(appState.localProcessing.descriptors.map(DesktopClientProjection.parser))
        }
        if request.method == "POST", path == "/document" {
            return openDocument(request.body, in: appState)
        }
        if request.method == "GET", path == "/document" {
            guard let document = appState.selectedDocument else {
                return .json([ClientDocument]())
            }
            return .json([project(document)])
        }
        if request.method == "GET", segments.count == 2, segments[0] == "document" {
            guard let document = matchingDocument(id: segments[1], in: appState) else {
                return notFound("document", segments[1])
            }
            return .json(project(document))
        }
        if request.method == "POST", segments.count == 3,
           segments[0] == "document", segments[2] == "parse" {
            return startParse(documentID: segments[1], body: request.body, in: appState)
        }
        if request.method == "GET", path == "/run" {
            appState.localProcessing.refreshRecentRuns()
            return .json(appState.localProcessing.recentRuns.map {
                DesktopClientProjection.run($0)
            })
        }
        if segments.count >= 2, segments[0] == "run" {
            let runID = segments[1]
            guard let run = appState.localProcessing.run(id: runID) else {
                return notFound("run", runID)
            }
            if request.method == "GET", segments.count == 2 {
                return .json(DesktopClientProjection.run(run))
            }
            if request.method == "GET", segments.count == 3, segments[2] == "artifacts" {
                do { return .json(try DesktopClientProjection.artifacts(for: run)) }
                catch { return .failure(status: 409, code: "artifacts_unavailable", message: error.localizedDescription) }
            }
            if request.method == "GET", segments.count == 3, segments[2] == "events" {
                return runEvents(run)
            }
            if request.method == "POST", segments.count == 3, segments[2] == "cancel" {
                guard appState.localProcessing.latestRun?.id == runID,
                      appState.localProcessing.isRunning else {
                    return .failure(status: 409, code: "run_not_active", message: "Only the active run can be canceled.")
                }
                appState.localProcessing.cancelRun()
                return .json(DesktopClientProjection.run(appState.localProcessing.run(id: runID) ?? run), status: 202)
            }
            if request.method == "POST", segments.count == 3, segments[2] == "resume" {
                return resume(run, in: appState)
            }
            if request.method == "POST", segments.count == 4,
               segments[2] == "redactions", segments[3] == "detect" {
                return await detectPII(run, in: appState)
            }
            if request.method == "POST", segments.count == 3, segments[2] == "detect" {
                return await detectPII(run, in: appState)
            }
            if request.method == "GET", segments.count == 3, segments[2] == "redactions" {
                return redactions(run, in: appState)
            }
        }
        if request.method == "GET", path == "/global/event" {
            return globalEvents(in: appState)
        }
        return .failure(status: 404, code: "route_not_found", message: "No client-protocol route matches \(request.method) \(path).")
    }

    private func openDocument(_ body: Data, in appState: AppState) -> DesktopHTTPResponse {
        guard let request = try? ClientJSON.decoder.decode(ClientDocumentRequest.self, from: body) else {
            return .failure(status: 400, code: "invalid_document", message: "Body must contain an absolute PDF source path.")
        }
        appState.openPDF(URL(fileURLWithPath: request.source))
        guard let document = appState.selectedDocument,
              document.filePath == URL(fileURLWithPath: request.source).standardizedFileURL.path else {
            return .failure(status: 409, code: "document_not_opened", message: appState.importError ?? "Okra could not open the PDF.")
        }
        let projected = DesktopClientProjection.document(document)
        openedAtByDocumentID[projected.id] = .now
        return .json(projected, status: 201)
    }

    private func startParse(
        documentID: String,
        body: Data,
        in appState: AppState
    ) -> DesktopHTTPResponse {
        guard let document = matchingDocument(id: documentID, in: appState) else {
            return notFound("document", documentID)
        }
        let request = (try? ClientJSON.decoder.decode(ClientParseRequest.self, from: body))
            ?? ClientParseRequest()
        let providerName = request.providerId ?? request.parserId
        guard let providerID = LocalProviderID(rawValue: providerName),
              appState.localProcessing.descriptors.contains(where: { $0.id == providerID }) else {
            return .failure(status: 400, code: "unknown_provider", message: "Unknown parser/provider \(providerName).")
        }
        appState.localProcessing.selectedProviderID = providerID
        let availability = appState.localProcessing.availability(for: providerID)
        guard availability.isReady else {
            return .failure(
                status: 409,
                code: "provider_setup_required",
                message: "\(availability.message) Open Okra.app → Plugins to review the model license and finish setup."
            )
        }
        guard let runID = appState.localProcessing.run(document: document),
              let run = appState.localProcessing.run(id: runID) else {
            return .failure(status: 409, code: "run_not_started", message: appState.localProcessing.statusMessage)
        }
        return .json(DesktopClientProjection.run(run, model: request.model), status: 202)
    }

    private func resume(_ run: LocalProcessingRun, in appState: AppState) -> DesktopHTTPResponse {
        if appState.selectedDocument?.filePath != run.sourcePath {
            appState.openPDF(URL(fileURLWithPath: run.sourcePath))
        }
        guard let document = appState.selectedDocument, document.filePath == run.sourcePath else {
            return .failure(status: 409, code: "source_missing", message: appState.importError ?? "The source PDF is unavailable.")
        }
        appState.localProcessing.selectRun(run)
        guard appState.localProcessing.canResumeLatestRun else {
            return .failure(status: 409, code: "run_not_resumable", message: "This run cannot be resumed in its current state.")
        }
        appState.localProcessing.resume(document: document)
        return .json(DesktopClientProjection.run(appState.localProcessing.run(id: run.id) ?? run), status: 202)
    }

    private func detectPII(_ run: LocalProcessingRun, in appState: AppState) async -> DesktopHTTPResponse {
        if appState.localProcessing.latestRun?.id != run.id {
            if appState.selectedDocument?.filePath != run.sourcePath {
                appState.openPDF(URL(fileURLWithPath: run.sourcePath))
            }
            appState.localProcessing.selectRun(run)
        }
        do {
            let detection = try await appState.localProcessing.redaction.detectForClient(runID: run.id)
            return .json(DesktopClientProjection.redaction(detection))
        } catch {
            return .failure(status: 409, code: "presidio_not_ready", message: "\(error.localizedDescription) Set up Presidio explicitly in Okra.app, then retry.")
        }
    }

    private func redactions(_ run: LocalProcessingRun, in appState: AppState) -> DesktopHTTPResponse {
        let coordinator = appState.localProcessing.redaction
        if let detection = coordinator.detectionForClient(run: run) {
            return .json(DesktopClientProjection.redaction(detection))
        }
        if coordinator.isDetectingForClient(runID: run.id) {
            return .json(ClientRedactionStatus(runId: run.id), status: 202)
        }
        return .failure(
            status: 404,
            code: "redactions_not_found",
            message: "No Presidio detection exists for run \(run.id)."
        )
    }

    private func project(_ document: LocalPDFDocument) -> ClientDocument {
        let id = DesktopClientProjection.documentID(for: document.filePath)
        return DesktopClientProjection.document(document, openedAt: openedAtByDocumentID[id] ?? .now)
    }

    private func matchingDocument(id: String, in appState: AppState) -> LocalPDFDocument? {
        guard let document = appState.selectedDocument,
              DesktopClientProjection.documentID(for: document.filePath) == id else { return nil }
        return document
    }

    private func runEvents(_ run: LocalProcessingRun) -> DesktopHTTPResponse {
        var events: [[String: Any]] = [[
            "protocol": OkraClientProtocol.version,
            "id": "\(run.id):started",
            "seq": 0,
            "createdAt": DesktopClientProjection.timestamp(run.startedAt),
            "type": "run.started",
            "run": jsonObject(DesktopClientProjection.run(run)),
        ]]
        for (index, page) in DesktopClientProjection.run(run).pages.enumerated() {
            events.append([
                "protocol": OkraClientProtocol.version,
                "id": "\(run.id):page:\(page.page)",
                "seq": index + 1,
                "createdAt": page.updatedAt,
                "type": "run.page",
                "runId": run.id,
                "page": jsonObject(page),
            ])
        }
        let seq = events.count
        if run.status == "succeeded", let artifacts = try? DesktopClientProjection.artifacts(for: run) {
            events.append([
                "protocol": OkraClientProtocol.version,
                "id": "\(run.id):completed",
                "seq": seq,
                "createdAt": DesktopClientProjection.timestamp(run.completedAt ?? .now),
                "type": "run.completed",
                "run": jsonObject(DesktopClientProjection.run(run)),
                "artifacts": jsonObject(artifacts),
            ])
        } else if run.status == "failed" {
            events.append([
                "protocol": OkraClientProtocol.version,
                "id": "\(run.id):failed",
                "seq": seq,
                "createdAt": DesktopClientProjection.timestamp(run.completedAt ?? .now),
                "type": "run.failed",
                "runId": run.id,
                "message": run.errorMessage ?? "Parse failed.",
            ])
        } else if run.status == "canceled" {
            events.append([
                "protocol": OkraClientProtocol.version,
                "id": "\(run.id):cancelled",
                "seq": seq,
                "createdAt": DesktopClientProjection.timestamp(run.completedAt ?? .now),
                "type": "run.cancelled",
                "runId": run.id,
            ])
        }
        return .eventStream(sse(events))
    }

    private func globalEvents(in appState: AppState) -> DesktopHTTPResponse {
        var events: [[String: Any]] = [[
            "protocol": OkraClientProtocol.version,
            "id": "server:\(ProcessInfo.processInfo.processIdentifier)",
            "seq": 0,
            "createdAt": DesktopClientProjection.timestamp(.now),
            "type": "server.connected",
            "host": "desktop_loopback",
        ]]
        if let document = appState.selectedDocument {
            events.append([
                "protocol": OkraClientProtocol.version,
                "id": "document:\(DesktopClientProjection.documentID(for: document.filePath))",
                "seq": 1,
                "createdAt": DesktopClientProjection.timestamp(.now),
                "type": "document.opened",
                "document": jsonObject(project(document)),
            ])
        }
        return .eventStream(sse(events))
    }

    private func sse(_ events: [[String: Any]]) -> Data {
        var data = Data("retry: 500\n".utf8)
        for event in events {
            guard let encoded = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]) else { continue }
            data.append(Data("data: ".utf8))
            data.append(encoded)
            data.append(Data("\n\n".utf8))
        }
        return data
    }

    private func jsonObject<T: Encodable>(_ value: T) -> Any {
        guard let data = try? ClientJSON.encoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) else { return [:] }
        return object
    }

    private func notFound(_ kind: String, _ id: String) -> DesktopHTTPResponse {
        .failure(status: 404, code: "\(kind)_not_found", message: "No \(kind) matches \(id).")
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0.0-rc.15"
    }
}
