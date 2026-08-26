import Foundation
import Network
import OkraClientCore
import OSLog

struct DesktopHTTPRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

struct DesktopHTTPResponse: Sendable {
    let status: Int
    let contentType: String
    let body: Data

    static func json<T: Encodable>(_ value: T, status: Int = 200) -> Self {
        do {
            return Self(
                status: status,
                contentType: "application/json; charset=utf-8",
                body: try ClientJSON.encoder().encode(value)
            )
        } catch {
            return failure(status: 500, code: "encoding_failed", message: error.localizedDescription)
        }
    }

    static func failure(status: Int, code: String, message: String) -> Self {
        json(ClientErrorEnvelope(code: code, message: message), status: status)
    }

    static func eventStream(_ body: Data) -> Self {
        Self(status: 200, contentType: "text/event-stream; charset=utf-8", body: body)
    }
}

final class DesktopClientHTTPHost {
    typealias Route = @Sendable (DesktopHTTPRequest) async -> DesktopHTTPResponse

    private let route: Route
    private let endpointURL: URL
    private let version: String
    private let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private let queue = DispatchQueue(label: "com.okrapdf.desktop.client-host")
    private let logger = Logger(subsystem: "com.okrapdf.desktop", category: "client-host")
    private var listener: NWListener?

    init(endpointURL: URL, version: String, route: @escaping Route) {
        self.endpointURL = endpointURL
        self.version = version
        self.route = route
    }

    func start() throws {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.receive(on: connection)
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard let port = listener?.port else { return }
                do {
                    try self.publishEndpoint(port: port.rawValue)
                    self.logger.notice("Local client host is ready on loopback")
                } catch {
                    self.logger.error("Could not publish local client endpoint: \(error.localizedDescription, privacy: .public)")
                    listener?.cancel()
                }
            case .failed(let error):
                self.logger.error("Local client host failed: \(error.localizedDescription, privacy: .public)")
                self.removeOwnedEndpoint()
            case .cancelled:
                self.removeOwnedEndpoint()
            default:
                break
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        removeOwnedEndpoint()
    }

    deinit {
        stop()
    }

    private func receive(on connection: NWConnection) {
        connection.start(queue: queue)
        receive(into: Data(), on: connection)
    }

    private func receive(into accumulated: Data, on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) { [weak self] data, _, complete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var accumulated = accumulated
            if let data { accumulated.append(data) }
            guard accumulated.count <= 1_048_576 else {
                self.send(.failure(status: 413, code: "request_too_large", message: "Request body exceeds 1 MiB."), on: connection)
                return
            }
            if let request = self.parseRequest(accumulated) {
                Task { [weak self] in
                    guard let self else { return }
                    let response: DesktopHTTPResponse
                    if request.headers["authorization"] != "Bearer \(self.token)" {
                        response = .failure(status: 401, code: "unauthorized", message: "Use the app-published client token.")
                    } else if request.headers[OkraClientProtocol.header] != OkraClientProtocol.version {
                        response = .failure(status: 409, code: "protocol_mismatch", message: "Expected \(OkraClientProtocol.version).")
                    } else {
                        response = await self.route(request)
                    }
                    self.send(response, on: connection)
                }
            } else if complete || error != nil {
                self.send(.failure(status: 400, code: "bad_request", message: "Incomplete HTTP request."), on: connection)
            } else {
                self.receive(into: accumulated, on: connection)
            }
        }
    }

    private func parseRequest(_ data: Data) -> DesktopHTTPRequest? {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: delimiter),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            return nil
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count == 3,
              requestParts[2].hasPrefix("HTTP/1.") else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        guard data.count - bodyStart >= contentLength else { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        return DesktopHTTPRequest(
            method: requestParts[0].uppercased(),
            path: requestParts[1],
            headers: headers,
            body: body
        )
    }

    private func send(_ response: DesktopHTTPResponse, on connection: NWConnection) {
        let reason: String
        switch response.status {
        case 200: reason = "OK"
        case 201: reason = "Created"
        case 202: reason = "Accepted"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        case 409: reason = "Conflict"
        case 413: reason = "Payload Too Large"
        default: reason = "Internal Server Error"
        }
        var data = Data(
            "HTTP/1.1 \(response.status) \(reason)\r\nContent-Type: \(response.contentType)\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\(OkraClientProtocol.header): \(OkraClientProtocol.version)\r\n\r\n".utf8
        )
        data.append(response.body)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func publishEndpoint(port: UInt16) throws {
        let directory = endpointURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let record = ClientEndpointRecord(
            baseURL: "http://127.0.0.1:\(port)",
            token: token,
            pid: ProcessInfo.processInfo.processIdentifier,
            version: version
        )
        try ClientJSON.encoder(pretty: true).encode(record).write(to: endpointURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: endpointURL.path)
    }

    private func removeOwnedEndpoint() {
        guard let data = try? Data(contentsOf: endpointURL),
              let record = try? ClientJSON.decoder.decode(ClientEndpointRecord.self, from: data),
              record.token == token else { return }
        try? FileManager.default.removeItem(at: endpointURL)
    }
}
