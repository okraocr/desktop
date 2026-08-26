import Darwin
import Foundation
import Security

private let protocolVersion = "okra.client.v1"
private let protocolHeader = "x-okra-client-protocol"

@main
struct OkraDesktopCLI {
    static func main() async {
        do {
            let command = try Command.parse(Array(CommandLine.arguments.dropFirst()))
            if case .help = command {
                print(Command.helpText)
                return
            }
            if case .version = command {
                print(cliVersion())
                return
            }

            let client = try await DesktopAppClient.connect()
            switch command {
            case .status(let json):
                let data = try await client.get("/global/health")
                try printJSONOrSummary(data, json: json) { object in
                    let version = object["version"] as? String ?? "unknown"
                    let host = object["host"] as? String ?? "desktop_loopback"
                    return "Okra Desktop \(version) is ready (\(host))."
                }
            case .providers(let json):
                let data = try await client.get("/provider")
                try printCatalog(data, json: json, kind: "provider")
            case .parsers(let json):
                let data = try await client.get("/parser")
                try printCatalog(data, json: json, kind: "parser")
            case .parse(let options):
                try await runParse(options, client: client)
            case .detect(let options):
                try await runDetection(options, client: client)
            case .help, .version:
                break
            }
        } catch {
            FileHandle.standardError.write(Data("okra: \(error.localizedDescription)\n".utf8))
            exit((error as? CLIError)?.exitCode ?? 1)
        }
    }

    private static func runParse(_ options: DocumentOptions, client: DesktopAppClient) async throws {
        let document = try await client.openDocument(options.source)
        let run = try await client.startParse(documentID: document.id, parserID: options.parserID)
        let finished = try await client.waitForRun(run.id)
        guard finished.status == "succeeded" else {
            throw CLIError.operation(finished.error ?? "The parse ended with status \(finished.status).")
        }
        let artifactsData = try await client.get("/run/\(urlPath(run.id))/artifacts")
        let artifacts = try JSONDecoder().decode(Artifacts.self, from: artifactsData)
        if let output = options.output {
            try writeArtifacts(artifacts, to: output)
            print(output.standardizedFileURL.path)
        } else if options.json {
            print(try prettyJSON(artifactsData))
        } else {
            print(artifacts.markdown)
        }
    }

    private static func runDetection(_ options: DocumentOptions, client: DesktopAppClient) async throws {
        let document = try await client.openDocument(options.source)
        let run = try await client.startParse(documentID: document.id, parserID: options.parserID)
        let finished = try await client.waitForRun(run.id)
        guard finished.status == "succeeded" else {
            throw CLIError.operation(finished.error ?? "The parse ended with status \(finished.status).")
        }
        _ = try await client.post("/run/\(urlPath(run.id))/detect", json: [:])
        let redactions = try await client.waitForRedactions(run.id)
        if let output = options.output {
            try FileManager.default.createDirectory(
                at: output.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try redactions.write(to: output, options: .atomic)
            print(output.standardizedFileURL.path)
        } else {
            print(try prettyJSON(redactions))
        }
    }

    private static func writeArtifacts(_ artifacts: Artifacts, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(artifacts.markdown.utf8).write(
            to: directory.appendingPathComponent("doc.md"),
            options: .atomic
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(artifacts.blocks).write(
            to: directory.appendingPathComponent("blocks.json"),
            options: .atomic
        )
        try encoder.encode(artifacts.manifest).write(
            to: directory.appendingPathComponent("manifest.json"),
            options: .atomic
        )
    }

    private static func printCatalog(_ data: Data, json: Bool, kind: String) throws {
        if json {
            print(try prettyJSON(data))
            return
        }
        let root = try jsonObject(data)
        let entries = root["data"] as? [[String: Any]] ?? []
        for entry in entries {
            let id = entry["id"] as? String ?? "unknown"
            let name = entry["displayName"] as? String ?? id
            let ready = entry["ready"] as? Bool == true ? "ready" : "not ready"
            let defaultMark = entry["isDefault"] as? Bool == true ? " · default" : ""
            print("\(id)\t\(name)\t\(ready)\(defaultMark)")
        }
        if entries.isEmpty { print("No \(kind)s reported by Okra Desktop.") }
    }

    private static func printJSONOrSummary(
        _ data: Data,
        json: Bool,
        summary: ([String: Any]) -> String
    ) throws {
        if json { print(try prettyJSON(data)) }
        else { print(summary(try jsonObject(data))) }
    }
}

private enum Command {
    case status(json: Bool)
    case providers(json: Bool)
    case parsers(json: Bool)
    case parse(DocumentOptions)
    case detect(DocumentOptions)
    case help
    case version

    static let helpText = """
    Usage:
      okra status [--json]
      okra providers [--json]
      okra parsers [--json]
      okra parse <document.pdf> [--parser <id>] [--output <directory>] [--json]
      okra chandra <document.pdf> [--output <directory>] [--json]
      okra detect <document.pdf> [--parser <id>] [--output <result.json>]
      okra presidio <document.pdf> [--parser <id>] [--output <result.json>]

    The CLI is a thin authenticated client for the running Okra Desktop app.
    It starts the app when needed. Chandra OCR 2 is the clean-install parser
    default; Presidio detection is always an explicit command.
    """

    static func parse(_ arguments: [String]) throws -> Self {
        guard let verb = arguments.first else { return .help }
        switch verb {
        case "help", "--help", "-h": return .help
        case "--version", "version": return .version
        case "status": return .status(json: arguments.dropFirst().contains("--json"))
        case "providers", "models": return .providers(json: arguments.dropFirst().contains("--json"))
        case "parsers": return .parsers(json: arguments.dropFirst().contains("--json"))
        case "parse": return .parse(try DocumentOptions.parse(Array(arguments.dropFirst())))
        case "chandra":
            var options = try DocumentOptions.parse(Array(arguments.dropFirst()))
            options.parserID = "chandra-ocr-2"
            return .parse(options)
        case "detect", "presidio", "prisideo":
            return .detect(try DocumentOptions.parse(Array(arguments.dropFirst())))
        default:
            throw CLIError.usage("Unknown command \(verb). Run `okra help`.")
        }
    }
}

private struct DocumentOptions {
    let source: URL
    var parserID = "chandra-ocr-2"
    var output: URL?
    var json = false

    static func parse(_ arguments: [String]) throws -> Self {
        var source: URL?
        var parserID = "chandra-ocr-2"
        var output: URL?
        var json = false
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--parser":
                index += 1
                guard index < arguments.count else { throw CLIError.usage("--parser requires an id.") }
                parserID = arguments[index]
            case "--output", "-o":
                index += 1
                guard index < arguments.count else { throw CLIError.usage("--output requires a path.") }
                output = URL(fileURLWithPath: arguments[index]).standardizedFileURL
            case "--json":
                json = true
            case let value where value.hasPrefix("-"):
                throw CLIError.usage("Unknown option \(value).")
            case let value:
                guard source == nil else { throw CLIError.usage("Only one PDF may be processed at a time.") }
                source = URL(fileURLWithPath: value).standardizedFileURL
            }
            index += 1
        }
        guard let source else { throw CLIError.usage("A PDF path is required.") }
        guard source.pathExtension.lowercased() == "pdf",
              FileManager.default.fileExists(atPath: source.path) else {
            throw CLIError.usage("The input must be an existing PDF: \(source.path)")
        }
        return DocumentOptions(source: source, parserID: parserID, output: output, json: json)
    }
}

private struct DesktopAppClient {
    let endpoint: EndpointState
    let session: URLSession

    static func connect() async throws -> Self {
        let session = URLSession(configuration: .ephemeral)
        if let endpoint = EndpointDiscovery.read(),
           let client = try? await validated(endpoint: endpoint, session: session) {
            return client
        }
        let endpoint = try await EndpointDiscovery.handshake()
        return try await validated(endpoint: endpoint, session: session)
    }

    private static func validated(endpoint: EndpointState, session: URLSession) async throws -> Self {
        guard endpoint.protocolVersion == protocolVersion else {
            throw CLIError.connection("Okra Desktop uses an incompatible client protocol.")
        }
        let client = DesktopAppClient(endpoint: endpoint, session: session)
        _ = try await client.get("/global/health")
        return client
    }

    func openDocument(_ source: URL) async throws -> ClientDocument {
        do {
            let data = try await post("/document", json: ["source": source.path])
            return try JSONDecoder().decode(ClientDocument.self, from: data)
        } catch let error as CLIError where error.isDocumentAccessRequired {
            try EndpointDiscovery.open(source)
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                if let data = try? await get("/document"),
                   let list = try? JSONDecoder().decode(ClientDocumentList.self, from: data),
                   let document = list.data.first(where: { $0.source == source.path }) {
                    return document
                }
                try await Task.sleep(for: .milliseconds(200))
            }
            throw CLIError.connection("Okra did not receive access to \(source.lastPathComponent).")
        }
    }

    func startParse(documentID: String, parserID: String) async throws -> ClientRun {
        let data = try await post(
            "/document/\(urlPath(documentID))/parse",
            json: ["parserId": parserID]
        )
        return try JSONDecoder().decode(ClientRun.self, from: data)
    }

    func waitForRun(_ runID: String) async throws -> ClientRun {
        var lastStatus = ""
        while true {
            let data = try await get("/run/\(urlPath(runID))")
            let run = try JSONDecoder().decode(ClientRun.self, from: data)
            if run.status != lastStatus {
                FileHandle.standardError.write(Data("\(run.status)…\n".utf8))
                lastStatus = run.status
            }
            if ["succeeded", "failed", "cancelled", "attention"].contains(run.status) {
                return run
            }
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    func waitForRedactions(_ runID: String) async throws -> Data {
        while true {
            let response = try await request(
                method: "GET",
                path: "/run/\(urlPath(runID))/redactions",
                body: nil,
                acceptedStatuses: [200, 202]
            )
            if response.status == 200 { return response.data }
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    func get(_ path: String) async throws -> Data {
        try await request(method: "GET", path: path, body: nil).data
    }

    func post(_ path: String, json: [String: String]) async throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        return try await request(method: "POST", path: path, body: body).data
    }

    private func request(
        method: String,
        path: String,
        body: Data?,
        acceptedStatuses: Set<Int> = [200, 201, 202]
    ) async throws -> (data: Data, status: Int) {
        guard let url = URL(string: "http://127.0.0.1:\(endpoint.port)\(path)") else {
            throw CLIError.connection("Could not construct the local Okra endpoint.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 35
        request.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CLIError.connection("Okra Desktop returned an invalid local response.")
        }
        guard http.value(forHTTPHeaderField: protocolHeader) == protocolVersion else {
            throw CLIError.connection("Okra Desktop returned an incompatible response.")
        }
        guard acceptedStatuses.contains(http.statusCode) else {
            let payload = try? JSONDecoder().decode(RemoteError.self, from: data)
            throw CLIError.remote(
                message: payload?.error ?? "Okra Desktop returned HTTP \(http.statusCode).",
                code: payload?.code,
                nextActions: payload?.nextActions ?? []
            )
        }
        return (data, http.statusCode)
    }
}

private enum EndpointDiscovery {
    private static let maximumCallbackBytes = 65_536

    static func read() -> EndpointState? {
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let state = try? JSONDecoder().decode(EndpointState.self, from: data) else {
                continue
            }
            return state
        }
        return nil
    }

    static func handshake() async throws -> EndpointState {
        try await Task.detached(priority: .userInitiated) {
            try handshakeSynchronously()
        }.value
    }

    static func open(_ document: URL) throws {
        var arguments = ["-gj"]
        if let app = appURL {
            arguments.append(contentsOf: ["-a", app.path])
        } else {
            arguments.append(contentsOf: ["-a", "Okra"])
        }
        arguments.append(document.path)
        try runOpen(arguments)
    }

    private static func runOpen(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CLIError.connection("LaunchServices could not open Okra.app.")
        }
    }

    private static var candidates: [URL] {
        var values: [URL] = []
        if let explicit = ProcessInfo.processInfo.environment["OKRA_DESKTOP_ENDPOINT_FILE"] {
            values.append(URL(fileURLWithPath: explicit))
        }
        return values
    }

    private static func handshakeSynchronously() throws -> EndpointState {
        let listener = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else {
            throw CLIError.connection("Could not create the Okra callback socket.")
        }
        defer { Darwin.close(listener) }

        var noSignal: Int32 = 1
        setsockopt(listener, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(
                    listener,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        guard bindResult == 0, Darwin.listen(listener, 1) == 0 else {
            throw CLIError.connection("Could not listen for the Okra app callback.")
        }

        var boundAddress = sockaddr_in()
        var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(listener, socketAddress, &boundLength)
            }
        }
        guard nameResult == 0 else {
            throw CLIError.connection("Could not resolve the Okra callback port.")
        }
        let port = UInt16(bigEndian: boundAddress.sin_port)
        let nonce = try secureNonce()
        try openCallback(port: port, nonce: nonce)

        var descriptor = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
        guard Darwin.poll(&descriptor, 1, 15_000) > 0,
              descriptor.revents & Int16(POLLIN) != 0 else {
            throw CLIError.connection(
                "Okra Desktop did not answer the local callback. Open Okra.app and retry."
            )
        }
        let client = Darwin.accept(listener, nil, nil)
        guard client >= 0 else {
            throw CLIError.connection("Okra Desktop could not complete the local callback.")
        }
        defer { Darwin.close(client) }
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let endpoint = try readCallback(from: client, nonce: nonce)
        let response = Data("HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
        response.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress {
                _ = Darwin.send(client, base, bytes.count, 0)
            }
        }
        return endpoint
    }

    private static func openCallback(port: UInt16, nonce: String) throws {
        var components = URLComponents()
        components.scheme = "okra"
        components.host = "client-connect"
        components.queryItems = [
            URLQueryItem(name: "port", value: String(port)),
            URLQueryItem(name: "nonce", value: nonce),
        ]
        guard let callbackURL = components.url else {
            throw CLIError.connection("Could not construct the Okra callback URL.")
        }
        var arguments = ["-gj"]
        if let app = appURL {
            arguments.append(contentsOf: ["-a", app.path])
        }
        arguments.append(callbackURL.absoluteString)
        try runOpen(arguments)
    }

    private static func readCallback(from socket: Int32, nonce: String) throws -> EndpointState {
        var data = Data()
        var headerEnd: Range<Data.Index>?
        while data.count <= maximumCallbackBytes {
            var buffer = [UInt8](repeating: 0, count: 4_096)
            let count = Darwin.recv(socket, &buffer, buffer.count, 0)
            guard count > 0 else {
                throw CLIError.connection("Okra Desktop sent an incomplete callback.")
            }
            data.append(buffer, count: count)
            headerEnd = data.range(of: Data("\r\n\r\n".utf8))
            if headerEnd != nil { break }
        }
        guard let headerEnd,
              let headerText = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else {
            throw CLIError.connection("Okra Desktop sent an invalid callback.")
        }
        var headers: [String: String] = [:]
        for line in headerText.components(separatedBy: "\r\n").dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
        }
        guard headers["authorization"] == "Bearer \(nonce)",
              let contentLength = Int(headers["content-length"] ?? ""),
              contentLength > 0,
              contentLength <= maximumCallbackBytes else {
            throw CLIError.connection("Okra Desktop callback authentication failed.")
        }
        let bodyStart = headerEnd.upperBound
        while data.count - bodyStart < contentLength {
            var buffer = [UInt8](
                repeating: 0,
                count: min(4_096, contentLength - (data.count - bodyStart))
            )
            let count = Darwin.recv(socket, &buffer, buffer.count, 0)
            guard count > 0 else {
                throw CLIError.connection("Okra Desktop sent an incomplete endpoint.")
            }
            data.append(buffer, count: count)
        }
        return try JSONDecoder().decode(
            EndpointState.self,
            from: Data(data[bodyStart..<(bodyStart + contentLength)])
        )
    }

    private static func secureNonce() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CLIError.connection("Could not create the Okra callback nonce.")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static var appURL: URL? {
        let environment = ProcessInfo.processInfo.environment
        var values: [URL] = []
        if let explicit = environment["OKRA_APP_PATH"] {
            values.append(URL(fileURLWithPath: explicit, isDirectory: true))
        }
        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0])
            .standardizedFileURL
            .deletingLastPathComponent()
        if ["MacOS", "Resources"].contains(executableDirectory.lastPathComponent),
           executableDirectory.deletingLastPathComponent().lastPathComponent == "Contents" {
            values.append(
                executableDirectory.deletingLastPathComponent().deletingLastPathComponent()
            )
        }
        values.append(URL(fileURLWithPath: "/Applications/Okra.app", isDirectory: true))
        values.append(
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Okra.app", isDirectory: true)
        )
        return values.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

private struct EndpointState: Decodable {
    let protocolVersion: String
    let port: UInt16
    let token: String
}

private struct ClientDocument: Decodable {
    let id: String
    let source: String
}

private struct ClientDocumentList: Decodable {
    let data: [ClientDocument]
}

private struct ClientRun: Decodable {
    let id: String
    let status: String
    let error: String?
}

private struct Artifacts: Codable {
    let markdown: String
    let blocks: [JSONValue]
    let manifest: JSONValue
}

private enum JSONValue: Codable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let decoded = try? value.decode(Bool.self) { self = .bool(decoded) }
        else if let decoded = try? value.decode(Double.self) { self = .number(decoded) }
        else if let decoded = try? value.decode(String.self) { self = .string(decoded) }
        else if let decoded = try? value.decode([String: JSONValue].self) { self = .object(decoded) }
        else { self = .array(try value.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let decoded): try value.encode(decoded)
        case .number(let decoded): try value.encode(decoded)
        case .bool(let decoded): try value.encode(decoded)
        case .object(let decoded): try value.encode(decoded)
        case .array(let decoded): try value.encode(decoded)
        case .null: try value.encodeNil()
        }
    }
}

private struct RemoteError: Decodable {
    let error: String
    let code: String?
    let nextActions: [String]?

    enum CodingKeys: String, CodingKey {
        case error, code
        case nextActions = "next_actions"
    }
}

private enum CLIError: LocalizedError {
    case usage(String)
    case connection(String)
    case operation(String)
    case remote(message: String, code: String?, nextActions: [String])

    var errorDescription: String? {
        switch self {
        case .usage(let message), .connection(let message), .operation(let message):
            return message
        case .remote(let message, _, let nextActions):
            guard nextActions.isEmpty == false else { return message }
            return ([message] + nextActions).joined(separator: "\n  ")
        }
    }

    var exitCode: Int32 {
        switch self {
        case .usage: 64
        case .connection: 69
        case .operation, .remote: 1
        }
    }

    var isDocumentAccessRequired: Bool {
        if case .remote(_, let code, _) = self { return code == "document_access_required" }
        return false
    }
}

private func jsonObject(_ data: Data) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw CLIError.operation("Okra Desktop returned invalid JSON.")
    }
    return object
}

private func prettyJSON(_ data: Data) throws -> String {
    let object = try JSONSerialization.jsonObject(with: data)
    let formatted = try JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    return String(decoding: formatted, as: UTF8.self)
}

private func urlPath(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
}

private func cliVersion() -> String {
    let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0])
        .standardizedFileURL
        .deletingLastPathComponent()
    if ["MacOS", "Resources"].contains(executableDirectory.lastPathComponent) {
        let infoURL = executableDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("Info.plist")
        if let info = NSDictionary(contentsOf: infoURL),
           let version = info["CFBundleShortVersionString"] as? String {
            return version
        }
    }
    return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
}
