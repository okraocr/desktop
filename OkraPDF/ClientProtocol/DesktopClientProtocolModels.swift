import Foundation

enum DesktopClientProtocol {
    static let version = "okra.client.v1"
    static let header = "x-okra-client-protocol"
}

enum DesktopClientCallback {
    static let scheme = "okra"
    static let host = "client-connect"
}

struct DesktopClientEndpointState: Codable, Equatable, Sendable {
    let protocolVersion: String
    let pid: Int32
    let port: UInt16
    let token: String
    let startedAt: String
}

enum DesktopClientProtocolPaths {
    static var endpointStateURL: URL? {
        if let override = ProcessInfo.processInfo.environment[
            "OKRA_DESKTOP_ENDPOINT_FILE"
        ], override.isEmpty == false {
            return URL(fileURLWithPath: override).standardizedFileURL
        }
        return nil
    }
}

struct DesktopClientHealth: Encodable, Equatable, Sendable {
    let object = "client_health"
    let `protocol` = DesktopClientProtocol.version
    let healthy = true
    let version: String
    let host = "desktop_loopback"
    let capabilities: [String]
}

struct DesktopClientProvider: Encodable, Equatable, Sendable {
    let id: String
    let displayName: String
    let api: String
    let envKeys: [String]
    let baseUrl: String?
    let defaultModel: String?
    let models: [DesktopClientModel]
    let keyHint: String
    let delivery: String
    let ready: Bool
    let status: String
    let isDefault: Bool
}

struct DesktopClientModel: Encodable, Equatable, Sendable {
    let id: String
    let displayName: String?
    let vision: Bool
}

struct DesktopClientParser: Encodable, Equatable, Sendable {
    let id: String
    let displayName: String
    let version: String
    let requires: String
    let defaults: [String: String]
    let ready: Bool
    let status: String
    let isDefault: Bool
}

struct DesktopClientDocument: Encodable, Equatable, Sendable {
    let object = "client_document"
    let id: String
    let title: String
    let source: String
    let pageCount: Int
    let openedAt: String
}

struct DesktopClientPageLifecycle: Encodable, Equatable, Sendable {
    let parserId: String
    let page: Int
    let state: String
    let detail: String?
    let updatedAt: String
}

struct DesktopClientRun: Encodable, Equatable, Sendable {
    let object = "client_run"
    let id: String
    let documentId: String
    let parserId: String
    let providerId: String?
    let model: String?
    let status: String
    let pageCount: Int
    let pages: [DesktopClientPageLifecycle]
    let createdAt: String
    let updatedAt: String
    let error: String?
}

struct DesktopClientBlock: Encodable, Equatable, Sendable {
    let label: String
    let bbox: [Double]
    let text: String
    let page: Int
}

struct DesktopClientManifest: Encodable, Equatable, Sendable {
    let parserId: String
    let providerId: String?
    let model: String?
    let pageCount: Int
    let durationMs: Double
    let warnings: [String]
}

struct DesktopClientArtifacts: Encodable, Equatable, Sendable {
    let markdown: String
    let blocks: [DesktopClientBlock]
    let manifest: DesktopClientManifest
}

struct DesktopClientRedactionCandidate: Encodable, Equatable, Sendable {
    let id: String
    let type: String
    let text: String
    let score: Double
    let source: String
    let page: Int
    let bbox: [Double]
}

struct DesktopClientRedactionDetection: Encodable, Equatable, Sendable {
    let object = "client_redaction_detection"
    let runId: String
    let engine = "presidio"
    let model: String?
    let createdAt: String
    let candidates: [DesktopClientRedactionCandidate]
}

struct DesktopClientList<Element: Encodable & Equatable & Sendable>: Encodable, Equatable, Sendable {
    let object: String
    let data: [Element]
}

struct DesktopClientError: Encodable, Equatable, Sendable {
    let object = "error"
    let error: String
    let code: String?
    let nextActions: [String]?

    enum CodingKeys: String, CodingKey {
        case object
        case error
        case code
        case nextActions = "next_actions"
    }
}

enum DesktopClientDates {
    static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func string(_ date: Date) -> String {
        formatter.string(from: date)
    }
}
