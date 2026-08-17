import AppKit
import Foundation
import PDFKit
import Testing
@testable import Okra

struct PresidioRedactionTests {
    @Test("Presidio ready marker rejects stale runtime versions")
    func readyMarkerValidation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("okra-presidio-marker-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let markerURL = root.appendingPathComponent(".ready")

        let current = PresidioReadyMarker(
            schemaVersion: 1,
            presidioVersion: "2.2.364",
            spacyModelVersion: "3.8.0",
            installedAt: "2026-08-17T00:00:00Z"
        )
        try JSONEncoder().encode(current).write(to: markerURL)
        #expect(PresidioReadyMarker.read(from: markerURL)?.matchesCurrentRuntime == true)

        let stale = PresidioReadyMarker(
            schemaVersion: 1,
            presidioVersion: "2.2.363",
            spacyModelVersion: "3.8.0",
            installedAt: "2026-08-17T00:00:00Z"
        )
        try JSONEncoder().encode(stale).write(to: markerURL)
        #expect(PresidioReadyMarker.read(from: markerURL)?.matchesCurrentRuntime == false)
    }

    @Test("Simulated loopback worker maps PII findings to source blocks")
    func simulationMapsFindingsToBlocks() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("okra-presidio-simulation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = PresidioRedactionService(rootURL: root, simulation: true)
        defer { Task { await service.shutdown() } }
        let redactionsURL = root.appendingPathComponent("redactions.json")

        let result = try await service.detect(
            runID: "run-1",
            document: structuredDocument(
                text: "Email taylor@example.com or call 415-555-0198.",
                bbox: StructuredExtractionBoundingBox(
                    x: -0.1,
                    y: 0.2,
                    width: 0.8,
                    height: 0.1,
                    unit: "normalized",
                    origin: "top-left"
                )
            ),
            ollamaModel: nil,
            redactionsURL: redactionsURL
        )
        await service.shutdown()

        #expect(result.runID == "run-1")
        #expect(Set(result.boxes.map(\.type)) == ["EMAIL_ADDRESS", "PHONE_NUMBER"])
        #expect(result.boxes.allSatisfy { $0.page == 1 })
        #expect(result.boxes.allSatisfy { abs($0.x) < 0.000_001 })
        #expect(result.boxes.allSatisfy { abs($0.width - 0.7) < 0.000_001 })
        #expect(result.boxes.allSatisfy { $0.source == "presidio" })
        let persisted = try RedactionDetection.load(from: redactionsURL)
        #expect(persisted.schemaVersion == result.schemaVersion)
        #expect(persisted.object == result.object)
        #expect(persisted.runID == result.runID)
        #expect(persisted.ollamaModel == result.ollamaModel)
        #expect(persisted.boxes == result.boxes)
        #expect(persisted.stats == result.stats)
        #expect(abs(persisted.createdAt.timeIntervalSince(result.createdAt)) < 1)
    }

    @Test("Redacted export rasterizes affected pages without changing the source")
    func exportRasterizesAffectedPages() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("okra-redacted-export-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Packages/OkraConformance/Tests/OkraConformanceTests/Corpus/upstream/qpdf-11-pages.pdf")
        let source = root.appendingPathComponent("source.pdf")
        let destination = root.appendingPathComponent("redacted.pdf")
        try FileManager.default.copyItem(at: fixture, to: source)
        let originalData = try Data(contentsOf: source)
        let originalDocument = try #require(PDFDocument(url: source))
        #expect(originalDocument.pageCount > 1)

        let box = RedactionBox(
            id: "redaction-1",
            page: 1,
            x: 0,
            y: 0,
            width: 1,
            height: 1,
            type: "TEST",
            text: "page one",
            score: 1,
            source: "presidio",
            blockID: "block-1"
        )
        try RedactedPDFExporter.export(
            sourceURL: source,
            destinationURL: destination,
            boxes: [box]
        )

        #expect(try Data(contentsOf: source) == originalData)
        let redacted = try #require(PDFDocument(url: destination))
        #expect(redacted.pageCount == originalDocument.pageCount)
        #expect(redacted.page(at: 0)?.string?.isEmpty != false)
    }

    private func structuredDocument(
        text: String,
        bbox: StructuredExtractionBoundingBox
    ) -> StructuredExtractionDocument {
        StructuredExtractionDocument(
            schemaVersion: 1,
            object: "local_extraction",
            provider: StructuredExtractionProvider(id: "apple-vision", name: "Apple Vision"),
            title: "fixture.pdf",
            pageCount: 1,
            completedPageCount: 1,
            complete: true,
            simulation: false,
            pages: [
                StructuredExtractionPage(
                    pageNumber: 1,
                    imageFile: "page-0001.png",
                    markdown: text,
                    plainText: text,
                    blocks: [
                        StructuredExtractionBlock(
                            id: "page-1-block-1",
                            type: "text",
                            sourceType: "vision-text-observation",
                            text: text,
                            bbox: bbox,
                            sourceBbox: nil,
                            sourceBboxScale: nil
                        ),
                    ],
                    diagnostics: StructuredExtractionDiagnostics(
                        rawCharacterCount: text.count,
                        decodedCharacterCount: text.count,
                        tokenArtifactCount: 0,
                        detectionCount: 1,
                        malformedDetectionCount: 0,
                        duplicateBlockCount: 0,
                        loopDetected: false,
                        warnings: [],
                        blockCount: 1
                    )
                ),
            ]
        )
    }
}
