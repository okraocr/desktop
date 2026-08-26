import Foundation
import OkraClientCore
import Darwin
import Security

@main
struct OkraCLI {
    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) async throws {
        guard let command = arguments.first else {
            printUsage()
            return
        }
        if ["help", "--help", "-h"].contains(command) {
            printUsage()
            return
        }
        if ["version", "--version", "-v"].contains(command) {
            print("okra \(bundledVersion)")
            return
        }

        let client = try await AppClient.connect()
        switch command {
        case "status":
            try await client.printJSON(path: "/global/health")
        case "providers", "provider":
            try await client.printJSON(path: "/provider")
        case "parsers", "parser":
            try await client.printJSON(path: "/parser")
        case "open":
            let path = try requiredArgument(arguments, at: 1, usage: "okra open <document.pdf>")
            let document = try await client.open(path: path)
            print(try pretty(document))
        case "parse":
            try await parse(arguments: arguments, client: client)
        case "chandra":
            try await parse(arguments: arguments, client: client, forcedProvider: "chandra-ocr-2")
        case "runs":
            try await client.printJSON(path: "/run")
        case "run":
            let id = try requiredArgument(arguments, at: 1, usage: "okra run <run-id>")
            try await client.printJSON(path: "/run/\(id)")
        case "events":
            let id = try requiredArgument(arguments, at: 1, usage: "okra events <run-id>")
            try await client.printText(path: "/run/\(id)/events", accept: "text/event-stream")
        case "artifacts":
            let id = try requiredArgument(arguments, at: 1, usage: "okra artifacts <run-id>")
            try await client.printJSON(path: "/run/\(id)/artifacts")
        case "detect", "presidio", "prisideo":
            try await detect(arguments: arguments, client: client)
        case "cancel":
            let id = try requiredArgument(arguments, at: 1, usage: "okra cancel <run-id>")
            try await client.printJSON(path: "/run/\(id)/cancel", method: "POST")
        case "resume":
            let id = try requiredArgument(arguments, at: 1, usage: "okra resume <run-id>")
            try await client.printJSON(path: "/run/\(id)/resume", method: "POST")
        default:
            throw CLIError.usage("Unknown command \"\(command)\". Run okra help.")
        }
    }

    private static func parse(
        arguments: [String],
        client: AppClient,
        forcedProvider: String? = nil
    ) async throws {
        var target: String?
        var provider = forcedProvider ?? "chandra-ocr-2"
        var detached = false
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--provider", "--parser":
                index += 1
                guard index < arguments.count else {
                    throw CLIError.usage("--provider requires a provider id")
                }
                if forcedProvider == nil {
                    provider = arguments[index]
                }
            case "--detach":
                detached = true
            default:
                guard target == nil else {
                    throw CLIError.usage("okra parse <document.pdf|document-id> [--provider <id>] [--detach]")
                }
                target = arguments[index]
            }
            index += 1
        }
        guard let target else {
            throw CLIError.usage("okra parse <document.pdf|document-id> [--provider <id>] [--detach]")
        }

        let documentID: String
        if target.lowercased().hasSuffix(".pdf") || FileManager.default.fileExists(atPath: target) {
            documentID = try await client.open(path: target).id
        } else {
            documentID = target
        }
        let run = try await client.startParse(documentID: documentID, provider: provider)
        if detached {
            print(try pretty(run))
            return
        }

        let current = try await client.waitForRun(run.id)
        print(try pretty(current))
        if current.status != "succeeded" {
            throw CLIError.runFailed(current.status)
        }
    }

    private static func detect(arguments: [String], client: AppClient) async throws {
        var target: String?
        var provider = "chandra-ocr-2"
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--provider", "--parser":
                index += 1
                guard index < arguments.count else {
                    throw CLIError.usage("--provider requires a provider id")
                }
                provider = arguments[index]
            default:
                guard target == nil else {
                    throw CLIError.usage("okra presidio <document.pdf|run-id> [--provider <id>]")
                }
                target = arguments[index]
            }
            index += 1
        }
        guard let target else {
            throw CLIError.usage("okra presidio <document.pdf|run-id> [--provider <id>]")
        }

        let runID: String
        if target.lowercased().hasSuffix(".pdf") || FileManager.default.fileExists(atPath: target) {
            let document = try await client.open(path: target)
            let run = try await client.startParse(documentID: document.id, provider: provider)
            let finished = try await client.waitForRun(run.id)
            guard finished.status == "succeeded" else {
                throw CLIError.runFailed(finished.status)
            }
            runID = run.id
        } else {
            runID = target
        }
        try await client.printJSON(path: "/run/\(runID)/detect", method: "POST")
    }

    private static func requiredArgument(
        _ arguments: [String],
        at index: Int,
        usage: String
    ) throws -> String {
        guard index < arguments.count else { throw CLIError.usage(usage) }
        return arguments[index]
    }

    private static var bundledVersion: String {
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
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0.0-rc.13"
    }

    private static func pretty<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try ClientJSON.encoder(pretty: true).encode(value), as: UTF8.self)
    }

    private static func printUsage() {
        print(
            """
            okra — command-line client for the running Okra app

            Usage:
              okra status
              okra providers
              okra parsers
              okra open <document.pdf>
              okra parse <document.pdf|document-id> [--provider <id>] [--detach]
              okra chandra <document.pdf> [--detach]
              okra runs
              okra run <run-id>
              okra events <run-id>
              okra artifacts <run-id>
              okra detect <document.pdf|run-id> [--provider <id>]
              okra presidio <document.pdf|run-id> [--provider <id>]
              okra cancel <run-id>
              okra resume <run-id>
              okra version

            Chandra OCR 2 is the default parser on eligible Macs. Model setup and
            license acceptance stay explicit in Okra.app. `detect` invokes the app's
            configured Presidio plugin; redaction export still requires human approval.
            The CLI starts or reconnects to Okra.app through LaunchServices when needed.
            """
        )
    }
}

private struct AppClient {
    let endpoint: ClientEndpointRecord
    let baseURL: URL

    static func connect() async throws -> Self {
        if ClientEndpointRecord.candidateURLs.isEmpty == false,
           let endpoint = try? ClientEndpointRecord.load(),
           let client = try? Self(endpoint: endpoint),
           (try? await client.request(path: "/global/health")) != nil {
            return client
        }
        let client = try Self(endpoint: try await EndpointDiscovery.handshake())
        _ = try await client.request(path: "/global/health")
        return client
    }

    init(endpoint: ClientEndpointRecord) throws {
        guard let baseURL = URL(string: endpoint.baseURL),
              baseURL.scheme == "http",
              ["127.0.0.1", "localhost", "::1"].contains(baseURL.host ?? "") else {
            throw ClientProtocolError.invalidEndpoint
        }
        self.endpoint = endpoint
        self.baseURL = baseURL
    }

    func open(path: String) async throws -> ClientDocument {
        let sourceURL = URL(fileURLWithPath: path).standardizedFileURL
        guard sourceURL.pathExtension.lowercased() == "pdf",
              FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw CLIError.usage("The input must be an existing PDF: \(sourceURL.path)")
        }

        try EndpointDiscovery.openDocument(sourceURL)
        for _ in 0..<50 {
            if let documents: [ClientDocument] = try? await send(path: "/document"),
               let document = documents.first(where: { $0.source == sourceURL.path }) {
                return document
            }
            try await Task.sleep(for: .milliseconds(200))
        }

        return try await send(
            path: "/document",
            method: "POST",
            body: ClientJSON.encoder().encode(ClientDocumentRequest(source: sourceURL.path))
        )
    }

    func startParse(documentID: String, provider: String) async throws -> ClientRun {
        let request = ClientParseRequest(parserId: provider, providerId: provider)
        return try await send(
            path: "/document/\(documentID)/parse",
            method: "POST",
            body: ClientJSON.encoder().encode(request)
        )
    }

    func waitForRun(_ runID: String) async throws -> ClientRun {
        var current: ClientRun = try await send(path: "/run/\(runID)")
        while ["queued", "running", "cancelling"].contains(current.status) {
            try await Task.sleep(for: .milliseconds(500))
            current = try await send(path: "/run/\(runID)")
        }
        return current
    }

    func send<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> T {
        let data = try await request(path: path, method: method, body: body)
        return try ClientJSON.decoder.decode(T.self, from: data)
    }

    func printJSON(path: String, method: String = "GET") async throws {
        let data = try await request(path: path, method: method)
        let object = try JSONSerialization.jsonObject(with: data)
        let formatted = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        print(String(decoding: formatted, as: UTF8.self))
    }

    func printText(path: String, accept: String) async throws {
        let data = try await request(path: path, accept: accept)
        print(String(decoding: data, as: UTF8.self), terminator: "")
    }

    private func request(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        accept: String = "application/json"
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              url.host == baseURL.host,
              url.port == baseURL.port else {
            throw ClientProtocolError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
        request.setValue(OkraClientProtocol.version, forHTTPHeaderField: OkraClientProtocol.header)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientProtocolError.invalidEndpoint
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? ClientJSON.decoder.decode(ClientErrorEnvelope.self, from: data))?
                .error.message ?? String(decoding: data, as: UTF8.self)
            throw ClientProtocolError.http(status: http.statusCode, message: message)
        }
        return data
    }
}

private enum EndpointDiscovery {
    private static let maximumCallbackBytes = 65_536

    static func handshake() async throws -> ClientEndpointRecord {
        try await Task.detached(priority: .userInitiated) {
            try handshakeSynchronously()
        }.value
    }

    static func openDocument(_ document: URL) throws {
        var arguments = ["-gj"]
        if let appURL {
            arguments.append(contentsOf: ["-a", appURL.path])
        } else {
            arguments.append(contentsOf: ["-a", "Okra"])
        }
        arguments.append(document.path)
        try runOpen(arguments)
    }

    private static func handshakeSynchronously() throws -> ClientEndpointRecord {
        let listener = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else {
            throw CLIError.connection("Could not create the Okra callback socket.")
        }
        defer { Darwin.close(listener) }

        var noSignal: Int32 = 1
        setsockopt(
            listener,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSignal,
            socklen_t(MemoryLayout<Int32>.size)
        )
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
                "Okra.app did not answer the authenticated local callback."
            )
        }
        let client = Darwin.accept(listener, nil, nil)
        guard client >= 0 else {
            throw CLIError.connection("Okra.app could not complete the local callback.")
        }
        defer { Darwin.close(client) }
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(
            client,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )
        let endpoint = try readCallback(from: client, nonce: nonce)
        let response = Data(
            "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8
        )
        response.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress {
                _ = Darwin.send(client, base, bytes.count, 0)
            }
        }
        return endpoint
    }

    private static func openCallback(port: UInt16, nonce: String) throws {
        var components = URLComponents()
        components.scheme = OkraClientCallback.scheme
        components.host = OkraClientCallback.host
        components.queryItems = [
            URLQueryItem(name: "port", value: String(port)),
            URLQueryItem(name: "nonce", value: nonce),
        ]
        guard let callbackURL = components.url else {
            throw CLIError.connection("Could not construct the Okra callback URL.")
        }
        var arguments = ["-gj"]
        if let appURL {
            arguments.append(contentsOf: ["-a", appURL.path])
        }
        arguments.append(callbackURL.absoluteString)
        try runOpen(arguments)
    }

    private static func readCallback(
        from socket: Int32,
        nonce: String
    ) throws -> ClientEndpointRecord {
        var data = Data()
        var headerEnd: Range<Data.Index>?
        while data.count <= maximumCallbackBytes {
            var buffer = [UInt8](repeating: 0, count: 4_096)
            let count = Darwin.recv(socket, &buffer, buffer.count, 0)
            guard count > 0 else {
                throw CLIError.connection("Okra.app sent an incomplete callback.")
            }
            data.append(buffer, count: count)
            headerEnd = data.range(of: Data("\r\n\r\n".utf8))
            if headerEnd != nil { break }
        }
        guard let headerEnd,
              let headerText = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else {
            throw CLIError.connection("Okra.app sent an invalid callback.")
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard lines.first == "POST \(OkraClientCallback.path) HTTP/1.1" else {
            throw CLIError.connection("Okra.app sent an unexpected callback request.")
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[String(line[..<colon]).lowercased()] = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
        }
        guard headers["authorization"] == "Bearer \(nonce)",
              headers[OkraClientProtocol.header] == OkraClientProtocol.version,
              let contentLength = Int(headers["content-length"] ?? ""),
              contentLength > 0,
              contentLength <= maximumCallbackBytes else {
            throw CLIError.connection("Okra.app callback authentication failed.")
        }
        let bodyStart = headerEnd.upperBound
        while data.count - bodyStart < contentLength {
            var buffer = [UInt8](
                repeating: 0,
                count: min(4_096, contentLength - (data.count - bodyStart))
            )
            let count = Darwin.recv(socket, &buffer, buffer.count, 0)
            guard count > 0 else {
                throw CLIError.connection("Okra.app sent an incomplete endpoint.")
            }
            data.append(buffer, count: count)
        }
        let endpoint = try ClientJSON.decoder.decode(
            ClientEndpointRecord.self,
            from: Data(data[bodyStart..<(bodyStart + contentLength)])
        )
        guard endpoint.protocolVersion == OkraClientProtocol.version else {
            throw ClientProtocolError.incompatibleProtocol(endpoint.protocolVersion)
        }
        return endpoint
    }

    private static func secureNonce() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CLIError.connection("Could not create the Okra callback nonce.")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
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

    private static var appURL: URL? {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [URL] = []
        if let explicit = environment["OKRA_APP_PATH"], explicit.isEmpty == false {
            candidates.append(URL(fileURLWithPath: explicit, isDirectory: true))
        }
        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0])
            .standardizedFileURL
            .deletingLastPathComponent()
        if ["MacOS", "Resources"].contains(executableDirectory.lastPathComponent),
           executableDirectory.deletingLastPathComponent().lastPathComponent == "Contents" {
            candidates.append(
                executableDirectory.deletingLastPathComponent().deletingLastPathComponent()
            )
        }
        candidates.append(URL(fileURLWithPath: "/Applications/Okra.app", isDirectory: true))
        candidates.append(
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Okra.app", isDirectory: true)
        )
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

private enum CLIError: LocalizedError {
    case usage(String)
    case connection(String)
    case runFailed(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message): return message
        case .connection(let message): return message
        case .runFailed(let status): return "parse finished with status \(status)"
        }
    }
}
