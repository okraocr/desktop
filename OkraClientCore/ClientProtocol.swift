import Foundation

public enum OkraClientProtocol {
    public static let version = "okra.client.v1"
    public static let header = "x-okra-client-protocol"
}

public enum OkraClientCallback {
    public static let scheme = "okra"
    public static let host = "client-connect"
    public static let path = "/endpoint"
}

public struct ClientEndpointRecord: Codable, Equatable, Sendable {
    public let protocolVersion: String
    public let baseURL: String
    public let token: String
    public let pid: Int32
    public let version: String

    public init(
        protocolVersion: String = OkraClientProtocol.version,
        baseURL: String,
        token: String,
        pid: Int32,
        version: String
    ) {
        self.protocolVersion = protocolVersion
        self.baseURL = baseURL
        self.token = token
        self.pid = pid
        self.version = version
    }

    public static var candidateURLs: [URL] {
        if let override = ProcessInfo.processInfo.environment["OKRA_CLIENT_ENDPOINT"],
           override.isEmpty == false {
            return [URL(fileURLWithPath: override).standardizedFileURL]
        }
        return []
    }

    public static func load() throws -> Self {
        for url in candidateURLs where FileManager.default.fileExists(atPath: url.path) {
            let record = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
            guard record.protocolVersion == OkraClientProtocol.version else {
                throw ClientProtocolError.incompatibleProtocol(record.protocolVersion)
            }
            return record
        }
        throw ClientProtocolError.appNotRunning
    }
}

public enum ClientProtocolError: LocalizedError {
    case appNotRunning
    case incompatibleProtocol(String)
    case invalidEndpoint
    case http(status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .appNotRunning:
            return "Okra.app could not be reached through LaunchServices."
        case .incompatibleProtocol(let version):
            return "Okra.app is using unsupported client protocol \(version)."
        case .invalidEndpoint:
            return "Okra.app published an invalid local endpoint."
        case .http(let status, let message):
            return "Okra.app returned HTTP \(status): \(message)"
        }
    }
}

public struct ClientHealth: Codable, Equatable, Sendable {
    public let object: String
    public let `protocol`: String
    public let healthy: Bool
    public let version: String
    public let host: String
    public let capabilities: [String]

    public init(version: String, capabilities: [String]) {
        object = "client_health"
        `protocol` = OkraClientProtocol.version
        healthy = true
        self.version = version
        host = "desktop_loopback"
        self.capabilities = capabilities
    }
}

public struct ClientModelSpec: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String?
    public let vision: Bool

    public init(id: String, displayName: String? = nil, vision: Bool) {
        self.id = id
        self.displayName = displayName
        self.vision = vision
    }
}

public struct ClientProviderSpec: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let api: String
    public let envKeys: [String]
    public let baseUrl: String?
    public let baseUrlEnvKey: String?
    public let defaultModel: String?
    public let models: [ClientModelSpec]
    public let keyHint: String
    public let delivery: String
    public let availability: String
    public let detail: String
    public let selected: Bool

    public init(
        id: String,
        displayName: String,
        api: String = "local",
        envKeys: [String] = [],
        baseUrl: String? = nil,
        baseUrlEnvKey: String? = nil,
        defaultModel: String? = nil,
        models: [ClientModelSpec] = [],
        keyHint: String = "No API key; runs on this Mac.",
        delivery: String,
        availability: String,
        detail: String,
        selected: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.api = api
        self.envKeys = envKeys
        self.baseUrl = baseUrl
        self.baseUrlEnvKey = baseUrlEnvKey
        self.defaultModel = defaultModel
        self.models = models
        self.keyHint = keyHint
        self.delivery = delivery
        self.availability = availability
        self.detail = detail
        self.selected = selected
    }
}

public struct ClientParserSpec: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let version: String
    public let requires: String
    public let defaults: [String: String]

    public init(
        id: String,
        displayName: String,
        version: String,
        requires: String = "none",
        defaults: [String: String] = [:]
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.requires = requires
        self.defaults = defaults
    }
}

public struct ClientDocument: Codable, Equatable, Sendable {
    public let object: String
    public let id: String
    public let title: String
    public let source: String
    public let pageCount: Int
    public let openedAt: String

    public init(id: String, title: String, source: String, pageCount: Int, openedAt: String) {
        object = "client_document"
        self.id = id
        self.title = title
        self.source = source
        self.pageCount = pageCount
        self.openedAt = openedAt
    }
}

public struct ClientDocumentRequest: Codable, Equatable, Sendable {
    public let source: String
    public init(source: String) { self.source = source }
}

public struct ClientParseRequest: Codable, Equatable, Sendable {
    public let parserId: String
    public let providerId: String?
    public let model: String?

    public init(parserId: String = "chandra-ocr-2", providerId: String? = nil, model: String? = nil) {
        self.parserId = parserId
        self.providerId = providerId
        self.model = model
    }
}

public struct ClientPageLifecycle: Codable, Equatable, Sendable {
    public let parserId: String
    public let page: Int
    public let state: String
    public let detail: String?
    public let updatedAt: String

    public init(parserId: String, page: Int, state: String, detail: String?, updatedAt: String) {
        self.parserId = parserId
        self.page = page
        self.state = state
        self.detail = detail
        self.updatedAt = updatedAt
    }
}

public struct ClientRun: Codable, Equatable, Sendable {
    public let object: String
    public let id: String
    public let documentId: String
    public let parserId: String
    public let providerId: String?
    public let model: String?
    public let status: String
    public let pageCount: Int
    public let pages: [ClientPageLifecycle]
    public let createdAt: String
    public let updatedAt: String

    public init(
        id: String,
        documentId: String,
        parserId: String,
        providerId: String?,
        model: String?,
        status: String,
        pageCount: Int,
        pages: [ClientPageLifecycle],
        createdAt: String,
        updatedAt: String
    ) {
        object = "client_run"
        self.id = id
        self.documentId = documentId
        self.parserId = parserId
        self.providerId = providerId
        self.model = model
        self.status = status
        self.pageCount = pageCount
        self.pages = pages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ClientLayoutBlock: Codable, Equatable, Sendable {
    public let label: String
    public let bbox: [Double]
    public let text: String
    public let page: Int

    public init(label: String, bbox: [Double], text: String, page: Int) {
        self.label = label
        self.bbox = bbox
        self.text = text
        self.page = page
    }
}

public struct ClientParseManifest: Codable, Equatable, Sendable {
    public let parserId: String
    public let providerId: String?
    public let model: String?
    public let pageCount: Int
    public let durationMs: Double
    public let warnings: [String]

    public init(
        parserId: String,
        providerId: String?,
        model: String?,
        pageCount: Int,
        durationMs: Double,
        warnings: [String]
    ) {
        self.parserId = parserId
        self.providerId = providerId
        self.model = model
        self.pageCount = pageCount
        self.durationMs = durationMs
        self.warnings = warnings
    }
}

public struct ClientArtifacts: Codable, Equatable, Sendable {
    public let markdown: String
    public let blocks: [ClientLayoutBlock]
    public let manifest: ClientParseManifest

    public init(markdown: String, blocks: [ClientLayoutBlock], manifest: ClientParseManifest) {
        self.markdown = markdown
        self.blocks = blocks
        self.manifest = manifest
    }
}

public struct ClientRedactionCandidate: Codable, Equatable, Sendable {
    public let id: String
    public let type: String
    public let text: String
    public let score: Double
    public let source: String
    public let page: Int
    public let bbox: [Double]

    public init(
        id: String,
        type: String,
        text: String,
        score: Double,
        source: String,
        page: Int,
        bbox: [Double]
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.score = score
        self.source = source
        self.page = page
        self.bbox = bbox
    }
}

public struct ClientRedactionDetection: Codable, Equatable, Sendable {
    public let object: String
    public let runId: String
    public let engine: String
    public let model: String?
    public let createdAt: String
    public let candidates: [ClientRedactionCandidate]

    public init(
        runId: String,
        model: String?,
        createdAt: String,
        candidates: [ClientRedactionCandidate]
    ) {
        object = "client_redaction_detection"
        self.runId = runId
        engine = "presidio"
        self.model = model
        self.createdAt = createdAt
        self.candidates = candidates
    }
}

public struct ClientRedactionStatus: Codable, Equatable, Sendable {
    public let object: String
    public let runId: String
    public let status: String
    public let engine: String

    public init(runId: String) {
        object = "client_redaction_status"
        self.runId = runId
        status = "running"
        engine = "presidio"
    }
}

public struct ClientErrorEnvelope: Codable, Equatable, Sendable {
    public struct Detail: Codable, Equatable, Sendable {
        public let code: String
        public let message: String
        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    public let error: Detail
    public init(code: String, message: String) {
        error = Detail(code: code, message: message)
    }
}

public enum ClientJSON {
    public static func encoder(pretty: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return encoder
    }

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
