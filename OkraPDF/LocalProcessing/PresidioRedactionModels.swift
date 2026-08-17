import Foundation

struct PresidioFinding: Codable, Equatable, Sendable {
    let entityType: String
    let start: Int
    let end: Int
    let score: Double
    let text: String?

    enum CodingKeys: String, CodingKey {
        case entityType = "entity_type"
        case start
        case end
        case score
        case text
    }
}

struct PresidioAnalyzePayload: Codable, Equatable, Sendable {
    let text: String
    let language: String
    let scoreThreshold: Double
    let ollamaModel: String?

    enum CodingKeys: String, CodingKey {
        case text
        case language
        case scoreThreshold = "score_threshold"
        case ollamaModel = "ollama_model"
    }
}

struct RedactionBox: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let page: Int
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let type: String
    let text: String
    let score: Double
    let source: String
    let blockID: String

    enum CodingKeys: String, CodingKey {
        case id
        case page
        case x
        case y
        case width = "w"
        case height = "h"
        case type
        case text
        case score
        case source
        case blockID = "blockId"
    }

    var boundingBox: StructuredExtractionBoundingBox {
        StructuredExtractionBoundingBox(
            x: x,
            y: y,
            width: width,
            height: height,
            unit: "normalized",
            origin: "top-left"
        )
    }

    var pdfOverlay: PDFBoundingBoxOverlay {
        PDFBoundingBoxOverlay(
            id: id,
            providerName: source,
            pageNumber: page,
            label: "Redaction",
            text: "\(type): \(text)",
            bbox: boundingBox
        )
    }
}

struct RedactionStats: Codable, Equatable, Sendable {
    let total: Int
    let byType: [String: Int]
    let bySource: [String: Int]
}

struct RedactionDetection: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let object: String
    let runID: String
    let createdAt: Date
    let ollamaModel: String?
    let boxes: [RedactionBox]
    let stats: RedactionStats

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case object
        case runID = "runId"
        case createdAt
        case ollamaModel
        case boxes
        case stats
    }

    static func make(runID: String, ollamaModel: String?, boxes: [RedactionBox]) -> Self {
        let byType = Dictionary(grouping: boxes, by: \RedactionBox.type)
            .mapValues(\.count)
        let bySource = Dictionary(grouping: boxes, by: \RedactionBox.source)
            .mapValues(\.count)
        return RedactionDetection(
            schemaVersion: 1,
            object: "pii_redaction_detection",
            runID: runID,
            createdAt: .now,
            ollamaModel: ollamaModel,
            boxes: boxes,
            stats: RedactionStats(total: boxes.count, byType: byType, bySource: bySource)
        )
    }

    static func load(from url: URL) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: Data(contentsOf: url))
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

struct PresidioReadyMarker: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let presidioVersion = "2.2.364"
    static let spacyModelVersion = "3.8.0"

    let schemaVersion: Int
    let presidioVersion: String
    let spacyModelVersion: String
    let installedAt: String

    var matchesCurrentRuntime: Bool {
        schemaVersion == Self.schemaVersion
            && presidioVersion == Self.presidioVersion
            && spacyModelVersion == Self.spacyModelVersion
    }

    static func read(from url: URL) -> Self? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}
