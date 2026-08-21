import AppKit
import Foundation
import PDFKit
import Testing
@testable import Okra

struct PresidioRedactionTests {
    @Test("Presidio installation publishes durable plugin progress")
    @MainActor
    func installationProgress() async throws {
        let workspace = try TestWorkspace(prefix: "okra-presidio-plugin-progress")
        let service = PresidioInstallationFixtureService()
        let coordinator = PresidioRedactionCoordinator(
            service: service,
            userDefaults: workspace.defaults
        )

        coordinator.install()
        try await waitUntil("Presidio installation phase to appear") {
            coordinator.setupProgress?.phase == .installingRuntime
        }

        #expect(coordinator.isInstalling)
        #expect(coordinator.setupProgress?.message.contains("Microsoft Presidio") == true)

        try await waitUntil("Presidio setup to finish") {
            coordinator.isInstalling == false
        }

        #expect(coordinator.availability == .ready)
        #expect(coordinator.setupProgress == nil)
        #expect(coordinator.errorMessage == nil)
        #expect(coordinator.statusMessage == "Microsoft Presidio is ready locally.")
    }

    @Test("Presidio installation can be canceled from Plugins")
    @MainActor
    func cancelInstallation() async throws {
        let workspace = try TestWorkspace(prefix: "okra-presidio-plugin-cancel")
        let service = PresidioInstallationFixtureService(suspendsUntilCanceled: true)
        let coordinator = PresidioRedactionCoordinator(
            service: service,
            userDefaults: workspace.defaults
        )

        coordinator.install()
        try await waitUntil("Presidio installation phase to appear") {
            coordinator.setupProgress?.phase == .installingRuntime
        }
        coordinator.cancelInstallation()
        try await waitUntil("Presidio installation cancellation to finish") {
            coordinator.isInstalling == false
        }

        #expect(coordinator.availability.isReady == false)
        #expect(coordinator.setupProgress == nil)
        #expect(coordinator.errorMessage == nil)
        #expect(coordinator.statusMessage.contains("canceled"))
    }

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
        let source = root.appendingPathComponent("source.pdf")
        let destination = root.appendingPathComponent("redacted.pdf")
        try makePDF(pageTexts: ["page one secret", "page two remains"]).write(to: source)
        let originalData = try Data(contentsOf: source)
        let originalDocument = try #require(PDFDocument(url: source))
        #expect(originalDocument.pageCount == 2)
        #expect(originalDocument.page(at: 0)?.string?.contains("page one secret") == true)

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
        #expect(redacted.page(at: 1)?.string?.contains("page two remains") == true)
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

    private func makePDF(pageTexts: [String]) throws -> Data {
        let document = PDFDocument()

        for (index, text) in pageTexts.enumerated() {
            let pageView = NSView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 30)
            label.frame = NSRect(x: 72, y: 640, width: 468, height: 60)
            pageView.addSubview(label)
            let pageData = pageView.dataWithPDF(inside: pageView.bounds)
            let pageDocument = try #require(PDFDocument(data: pageData))
            let page = try #require(pageDocument.page(at: 0))
            document.insert(page, at: index)
        }

        return try #require(document.dataRepresentation())
    }
}

private final class PresidioInstallationFixtureService: PresidioRedactionServicing {
    private(set) var isReady = false
    let suspendsUntilCanceled: Bool

    init(suspendsUntilCanceled: Bool = false) {
        self.suspendsUntilCanceled = suspendsUntilCanceled
    }

    func availability() async -> LocalProviderAvailability {
        isReady
            ? .ready
            : .setupRequired("Microsoft Presidio 2.2.364 + English spaCy model")
    }

    func install(
        progress: @escaping @Sendable (LocalProviderSetupProgress) -> Void
    ) async throws {
        progress(
            LocalProviderSetupProgress(
                phase: .preparing,
                fraction: nil,
                message: "Preparing the Presidio plugin…"
            )
        )
        progress(
            LocalProviderSetupProgress(
                phase: .installingRuntime,
                fraction: nil,
                message: "Installing Microsoft Presidio…"
            )
        )

        if suspendsUntilCanceled {
            try await Task.sleep(for: .seconds(60))
        } else {
            try await Task.sleep(for: .milliseconds(100))
        }

        try Task.checkCancellation()
        progress(
            LocalProviderSetupProgress(
                phase: .verifying,
                fraction: 0.95,
                message: "Verifying Presidio…"
            )
        )
        isReady = true
        progress(
            LocalProviderSetupProgress(
                phase: .ready,
                fraction: 1,
                message: "Microsoft Presidio is ready locally."
            )
        )
    }

    func detect(
        runID: String,
        document: StructuredExtractionDocument,
        ollamaModel: String?,
        redactionsURL: URL
    ) async throws -> RedactionDetection {
        throw PresidioInstallationFixtureError.unexpectedDetection
    }

    func shutdown() async {}
}

private enum PresidioInstallationFixtureError: Error {
    case unexpectedDetection
}
