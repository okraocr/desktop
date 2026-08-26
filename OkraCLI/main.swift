import Foundation
import OkraClientCore
import Darwin

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

        let client = try AppClient(endpoint: ClientEndpointRecord.load())
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
        case "detect", "presidio":
            let id = try requiredArgument(arguments, at: 1, usage: "okra detect <run-id>")
            try await client.printJSON(path: "/run/\(id)/redactions/detect", method: "POST")
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

    private static func parse(arguments: [String], client: AppClient) async throws {
        var target: String?
        var provider = "chandra-ocr-2"
        var detached = false
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--provider", "--parser":
                index += 1
                guard index < arguments.count else {
                    throw CLIError.usage("--provider requires a provider id")
                }
                provider = arguments[index]
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
        let request = ClientParseRequest(parserId: provider, providerId: provider)
        let run: ClientRun = try await client.send(
            path: "/document/\(documentID)/parse",
            method: "POST",
            body: ClientJSON.encoder().encode(request)
        )
        if detached {
            print(try pretty(run))
            return
        }

        var current = run
        while ["queued", "running", "cancelling"].contains(current.status) {
            try await Task.sleep(for: .milliseconds(500))
            current = try await client.send(path: "/run/\(run.id)")
        }
        print(try pretty(current))
        if current.status != "succeeded" {
            throw CLIError.runFailed(current.status)
        }
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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
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
              okra runs
              okra run <run-id>
              okra events <run-id>
              okra artifacts <run-id>
              okra detect <run-id>
              okra cancel <run-id>
              okra resume <run-id>
              okra version

            Chandra OCR 2 is the default parser on eligible Macs. Model setup and
            license acceptance stay explicit in Okra.app. `detect` invokes the app's
            configured Presidio plugin; redaction export still requires human approval.
            """
        )
    }
}

private struct AppClient {
    let endpoint: ClientEndpointRecord
    let baseURL: URL

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
        let source = URL(fileURLWithPath: path).standardizedFileURL.path
        return try await send(
            path: "/document",
            method: "POST",
            body: ClientJSON.encoder().encode(ClientDocumentRequest(source: source))
        )
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

private enum CLIError: LocalizedError {
    case usage(String)
    case runFailed(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message): return message
        case .runFailed(let status): return "parse finished with status \(status)"
        }
    }
}
