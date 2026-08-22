import Foundation

struct OllamaModel: Identifiable, Equatable, Sendable {
    let name: String
    let size: Int64
    let digest: String
    let family: String?
    let parameterSize: String?
    let quantizationLevel: String?
    let capabilities: Set<String>

    var id: String { name }
    var supportsVision: Bool { capabilities.contains("vision") }
}

struct OllamaHTTPTransport: Sendable {
    let data: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let live = OllamaHTTPTransport { request in
        try await URLSession.shared.data(for: request)
    }
}

/// HTTP-only adapter for the local Ollama service.
///
/// Ollama owns installation, model downloads, and its model store. Okra only
/// talks to the documented localhost API and never shells out to the Ollama CLI
/// or inspects `~/.ollama`.
struct OllamaClient: Sendable {
    static let defaultBaseURL = URL(string: "http://127.0.0.1:11434")!

    let baseURL: URL
    private let transport: OllamaHTTPTransport

    init(
        baseURL: URL = Self.defaultBaseURL,
        transport: OllamaHTTPTransport = .live
    ) {
        self.baseURL = baseURL
        self.transport = transport
    }

    func listModels() async throws -> [OllamaModel] {
        let response: TagsResponse = try await send(path: "/api/tags", method: "GET")
        var models: [OllamaModel] = []
        for summary in response.models {
            try Task.checkCancellation()
            let detail = try await showModel(named: summary.model ?? summary.name)
            models.append(
                OllamaModel(
                    name: summary.model ?? summary.name,
                    size: summary.size,
                    digest: summary.digest,
                    family: summary.details?.family ?? detail.details?.family,
                    parameterSize: summary.details?.parameterSize ?? detail.details?.parameterSize,
                    quantizationLevel: summary.details?.quantizationLevel
                        ?? detail.details?.quantizationLevel,
                    capabilities: Set(detail.capabilities ?? [])
                )
            )
        }
        return models.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func showModel(named model: String) async throws -> ShowResponse {
        try await send(
            path: "/api/show",
            method: "POST",
            body: ShowRequest(model: model)
        )
    }

    func extractMarkdown(model: String, imageURL: URL) async throws -> String {
        let imageData = try Data(contentsOf: imageURL)
        let request = ChatRequest(
            model: model,
            messages: [
                ChatMessage(
                    role: "user",
                    content: Self.documentPrompt,
                    images: [imageData.base64EncodedString()]
                ),
            ],
            stream: false,
            options: ChatOptions(temperature: 0)
        )
        let response: ChatResponse = try await send(
            path: "/api/chat",
            method: "POST",
            body: request,
            timeoutInterval: 1_800
        )
        let markdown = response.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard markdown.isEmpty == false else {
            throw LocalProcessingError.missingOutput("Ollama model \(model)")
        }
        return Self.stripOuterMarkdownFence(markdown)
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        timeoutInterval: TimeInterval = 10
    ) async throws -> Response {
        try await send(
            path: path,
            method: method,
            encodedBody: nil,
            timeoutInterval: timeoutInterval
        )
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body,
        timeoutInterval: TimeInterval = 10
    ) async throws -> Response {
        try await send(
            path: path,
            method: method,
            encodedBody: try JSONEncoder().encode(body),
            timeoutInterval: timeoutInterval
        )
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        encodedBody: Data?,
        timeoutInterval: TimeInterval
    ) async throws -> Response {
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = method
        request.httpBody = encodedBody
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if encodedBody != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await transport.data(request)
            guard let http = response as? HTTPURLResponse else {
                throw OllamaClientError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                let serverError = try? JSONDecoder().decode(ServerError.self, from: data)
                throw OllamaClientError.server(
                    status: http.statusCode,
                    message: serverError?.error
                )
            }
            do {
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw OllamaClientError.invalidPayload(error.localizedDescription)
            }
        } catch let error as OllamaClientError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw OllamaClientError.unreachable(baseURL.host ?? "localhost")
        }
    }

    private static func stripOuterMarkdownFence(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 2,
              lines.first?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true,
              lines.last?.trimmingCharacters(in: .whitespaces) == "```" else {
            return text
        }
        return lines.dropFirst().dropLast().joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let documentPrompt = """
    Transcribe this document page into accurate Markdown. Preserve reading order, headings, lists, tables, code, and formulas. Do not describe the page or add commentary. Return only the page content in Markdown.
    """

    private struct TagsResponse: Decodable {
        let models: [ModelSummary]
    }

    private struct ModelSummary: Decodable {
        let name: String
        let model: String?
        let size: Int64
        let digest: String
        let details: ModelDetails?
    }

    struct ShowResponse: Decodable, Sendable {
        let details: ModelDetails?
        let capabilities: [String]?
    }

    struct ModelDetails: Decodable, Sendable {
        let family: String?
        let parameterSize: String?
        let quantizationLevel: String?

        enum CodingKeys: String, CodingKey {
            case family
            case parameterSize = "parameter_size"
            case quantizationLevel = "quantization_level"
        }
    }

    private struct ShowRequest: Encodable {
        let model: String
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let stream: Bool
        let options: ChatOptions
    }

    private struct ChatMessage: Codable {
        let role: String
        let content: String
        let images: [String]?
    }

    private struct ChatOptions: Encodable {
        let temperature: Int
    }

    private struct ChatResponse: Decodable {
        let message: ChatMessage
    }

    private struct ServerError: Decodable {
        let error: String
    }
}

enum OllamaClientError: LocalizedError, Equatable {
    case unreachable(String)
    case invalidResponse
    case invalidPayload(String)
    case server(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .unreachable:
            return "Ollama is not responding at http://127.0.0.1:11434. Start Ollama, then refresh models."
        case .invalidResponse:
            return "Ollama returned an invalid HTTP response."
        case .invalidPayload:
            return "Ollama returned model data Okra could not read."
        case .server(let status, let message):
            if let detail = message?.trimmingCharacters(in: .whitespacesAndNewlines),
               detail.isEmpty == false {
                return "Ollama returned HTTP \(status): \(detail)"
            }
            return "Ollama returned HTTP \(status)."
        }
    }
}

enum OllamaConnectionState: Equatable, Sendable {
    case idle
    case refreshing
    case connected
    case unavailable(String)
}

/// Thread-safe selection shared by the UI-facing coordinator and both Ollama
/// parsing providers. It stores only API-discovered model metadata.
final class OllamaIntegrationState: @unchecked Sendable {
    private let lock = NSLock()
    private var connection: OllamaConnectionState = .idle
    private var models: [OllamaModel] = []
    private var selectedModelName: String?

    init(selectedModelName: String?) {
        self.selectedModelName = selectedModelName
    }

    func snapshot() -> (
        connection: OllamaConnectionState,
        models: [OllamaModel],
        selectedModelName: String?
    ) {
        lock.withLock { (connection, models, selectedModelName) }
    }

    func beginRefresh() {
        lock.withLock { connection = .refreshing }
    }

    func connect(models: [OllamaModel], selectedModelName: String?) {
        lock.withLock {
            connection = .connected
            self.models = models
            self.selectedModelName = selectedModelName
        }
    }

    func fail(message: String) {
        lock.withLock { connection = .unavailable(message) }
    }

    func select(modelName: String?) {
        lock.withLock { selectedModelName = modelName }
    }
}
