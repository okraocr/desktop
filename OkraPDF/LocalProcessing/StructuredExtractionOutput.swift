import Foundation

struct StructuredExtractionDocument: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let object: String
    let provider: StructuredExtractionProvider
    let title: String
    let pageCount: Int
    let completedPageCount: Int
    let complete: Bool
    let simulation: Bool
    let pages: [StructuredExtractionPage]

    static func load(from url: URL) throws -> StructuredExtractionDocument {
        try JSONDecoder().decode(
            StructuredExtractionDocument.self,
            from: Data(contentsOf: url)
        )
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

struct StructuredExtractionProvider: Codable, Equatable, Sendable {
    let id: String
    let name: String
}

struct StructuredExtractionPage: Codable, Equatable, Identifiable, Sendable {
    var id: Int { pageNumber }

    let pageNumber: Int
    let imageFile: String
    let markdown: String
    let plainText: String
    let blocks: [StructuredExtractionBlock]
    let diagnostics: StructuredExtractionDiagnostics
    let provenance: String?

    init(
        pageNumber: Int,
        imageFile: String,
        markdown: String,
        plainText: String,
        blocks: [StructuredExtractionBlock],
        diagnostics: StructuredExtractionDiagnostics,
        provenance: String? = nil
    ) {
        self.pageNumber = pageNumber
        self.imageFile = imageFile
        self.markdown = markdown
        self.plainText = plainText
        self.blocks = blocks
        self.diagnostics = diagnostics
        self.provenance = provenance
    }

    static func load(from url: URL) throws -> StructuredExtractionPage {
        try JSONDecoder().decode(
            StructuredExtractionPage.self,
            from: Data(contentsOf: url)
        )
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    func routed(
        to pageNumber: Int,
        imageFile: String,
        provenance: String?
    ) -> StructuredExtractionPage {
        StructuredExtractionPage(
            pageNumber: pageNumber,
            imageFile: imageFile,
            markdown: markdown,
            plainText: plainText,
            blocks: blocks.enumerated().map { index, block in
                StructuredExtractionBlock(
                    id: "page-\(pageNumber)-block-\(index + 1)",
                    type: block.type,
                    sourceType: block.sourceType,
                    text: block.text,
                    html: block.html,
                    bbox: block.bbox,
                    sourceBbox: block.sourceBbox,
                    sourceBboxScale: block.sourceBboxScale
                )
            },
            diagnostics: diagnostics,
            provenance: provenance
        )
    }
}

struct StructuredExtractionBlock: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let type: String
    let sourceType: String
    let text: String
    let html: String?
    let bbox: StructuredExtractionBoundingBox?
    let sourceBbox: [Double]?
    let sourceBboxScale: Int?

    init(
        id: String,
        type: String,
        sourceType: String,
        text: String,
        html: String? = nil,
        bbox: StructuredExtractionBoundingBox?,
        sourceBbox: [Double]?,
        sourceBboxScale: Int?
    ) {
        self.id = id
        self.type = type
        self.sourceType = sourceType
        self.text = text
        self.html = html
        self.bbox = bbox
        self.sourceBbox = sourceBbox
        self.sourceBboxScale = sourceBboxScale
    }

    var displayText: String {
        guard type == "table" else { return text }
        return text
            .replacingOccurrences(of: "</td>", with: "  |  ", options: .caseInsensitive)
            .replacingOccurrences(of: "</th>", with: "  |  ", options: .caseInsensitive)
            .replacingOccurrences(of: "</tr>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct StructuredExtractionBoundingBox: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let unit: String
    let origin: String

    var compactLabel: String {
        let xPercent = Int((x * 100).rounded())
        let yPercent = Int((y * 100).rounded())
        let widthPercent = Int((width * 100).rounded())
        let heightPercent = Int((height * 100).rounded())
        return "x \(xPercent)% · y \(yPercent)% · \(widthPercent)% × \(heightPercent)%"
    }
}

struct StructuredExtractionDiagnostics: Codable, Equatable, Sendable {
    let rawCharacterCount: Int
    let decodedCharacterCount: Int
    let tokenArtifactCount: Int
    let detectionCount: Int
    let malformedDetectionCount: Int
    let duplicateBlockCount: Int
    let loopDetected: Bool
    let warnings: [String]
    let blockCount: Int?
    let groundedBlockCount: Int?
    let ungroundedBlockCount: Int?

    init(
        rawCharacterCount: Int,
        decodedCharacterCount: Int,
        tokenArtifactCount: Int,
        detectionCount: Int,
        malformedDetectionCount: Int,
        duplicateBlockCount: Int,
        loopDetected: Bool,
        warnings: [String],
        blockCount: Int? = nil,
        groundedBlockCount: Int? = nil,
        ungroundedBlockCount: Int? = nil
    ) {
        self.rawCharacterCount = rawCharacterCount
        self.decodedCharacterCount = decodedCharacterCount
        self.tokenArtifactCount = tokenArtifactCount
        self.detectionCount = detectionCount
        self.malformedDetectionCount = malformedDetectionCount
        self.duplicateBlockCount = duplicateBlockCount
        self.loopDetected = loopDetected
        self.warnings = warnings
        self.blockCount = blockCount
        self.groundedBlockCount = groundedBlockCount
        self.ungroundedBlockCount = ungroundedBlockCount
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rawCharacterCount = try container.decodeIfPresent(
            Int.self,
            forKey: .rawCharacterCount
        ) ?? 0
        decodedCharacterCount = try container.decodeIfPresent(
            Int.self,
            forKey: .decodedCharacterCount
        ) ?? 0
        tokenArtifactCount = try container.decodeIfPresent(
            Int.self,
            forKey: .tokenArtifactCount
        ) ?? 0
        detectionCount = try container.decodeIfPresent(
            Int.self,
            forKey: .detectionCount
        ) ?? 0
        malformedDetectionCount = try container.decodeIfPresent(
            Int.self,
            forKey: .malformedDetectionCount
        ) ?? 0
        duplicateBlockCount = try container.decodeIfPresent(
            Int.self,
            forKey: .duplicateBlockCount
        ) ?? 0
        loopDetected = try container.decodeIfPresent(
            Bool.self,
            forKey: .loopDetected
        ) ?? false
        warnings = try container.decodeIfPresent(
            [String].self,
            forKey: .warnings
        ) ?? []
        blockCount = try container.decodeIfPresent(
            Int.self,
            forKey: .blockCount
        )
        groundedBlockCount = try container.decodeIfPresent(
            Int.self,
            forKey: .groundedBlockCount
        )
        ungroundedBlockCount = try container.decodeIfPresent(
            Int.self,
            forKey: .ungroundedBlockCount
        )
    }
}
