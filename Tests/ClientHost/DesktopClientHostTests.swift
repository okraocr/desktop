import Foundation
import OkraClientCore
import Testing
@testable import Okra

struct DesktopClientHostTests {
    @Test("The client host binds to loopback and requires its published token")
    func loopbackHostRequiresAuthentication() async throws {
        let workspace = try TestWorkspace(prefix: "okra-client-host")
        let endpointURL = workspace.root.appendingPathComponent("client-endpoint.json")
        let host = DesktopClientHTTPHost(
            endpointURL: endpointURL,
            version: "test",
            route: { request in
                guard request.path == "/global/health" else {
                    return .failure(status: 404, code: "not_found", message: "Not found")
                }
                return .json(ClientHealth(version: "test", capabilities: ["parse"]))
            }
        )
        try host.start()
        defer { host.stop() }

        try await waitUntil("client endpoint to be published") {
            FileManager.default.fileExists(atPath: endpointURL.path)
        }
        let endpoint = try ClientJSON.decoder.decode(
            ClientEndpointRecord.self,
            from: Data(contentsOf: endpointURL)
        )
        let baseURL = try #require(URL(string: endpoint.baseURL))
        #expect(baseURL.host == "127.0.0.1")

        var unauthorized = URLRequest(url: baseURL.appendingPathComponent("global/health"))
        unauthorized.setValue(OkraClientProtocol.version, forHTTPHeaderField: OkraClientProtocol.header)
        let (_, unauthorizedResponse) = try await URLSession.shared.data(for: unauthorized)
        #expect((unauthorizedResponse as? HTTPURLResponse)?.statusCode == 401)

        var authorized = unauthorized
        authorized.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
        let (data, authorizedResponse) = try await URLSession.shared.data(for: authorized)
        #expect((authorizedResponse as? HTTPURLResponse)?.statusCode == 200)
        let health = try ClientJSON.decoder.decode(ClientHealth.self, from: data)
        #expect(health.protocol == OkraClientProtocol.version)
        #expect(health.host == "desktop_loopback")
    }

    @Test("Desktop boxes convert explicitly to canonical 0-1000 coordinates")
    func artifactsUseCanonicalCoordinates() throws {
        let workspace = try TestWorkspace(prefix: "okra-client-artifacts")
        try FileManager.default.createDirectory(at: workspace.root, withIntermediateDirectories: true)
        let outputURL = workspace.root.appendingPathComponent("result.md")
        let structuredURL = workspace.root.appendingPathComponent("result.json")
        try "hello".write(to: outputURL, atomically: true, encoding: .utf8)
        let structured = StructuredExtractionDocument(
            schemaVersion: 1,
            object: "structured_extraction",
            provider: StructuredExtractionProvider(id: "chandra-ocr-2", name: "Chandra OCR 2"),
            title: "fixture",
            pageCount: 1,
            completedPageCount: 1,
            complete: true,
            simulation: false,
            pages: [
                StructuredExtractionPage(
                    pageNumber: 1,
                    imageFile: "page-1.png",
                    markdown: "hello",
                    plainText: "hello",
                    blocks: [
                        StructuredExtractionBlock(
                            id: "block-1",
                            type: "title",
                            sourceType: "title",
                            text: "hello",
                            bbox: StructuredExtractionBoundingBox(
                                x: 0.125,
                                y: 0.25,
                                width: 0.25,
                                height: 0.5,
                                unit: "normalized",
                                origin: "top-left"
                            ),
                            sourceBbox: nil,
                            sourceBboxScale: nil
                        ),
                    ],
                    diagnostics: StructuredExtractionDiagnostics(
                        rawCharacterCount: 5,
                        decodedCharacterCount: 5,
                        tokenArtifactCount: 0,
                        detectionCount: 1,
                        malformedDetectionCount: 0,
                        duplicateBlockCount: 0,
                        loopDetected: false,
                        warnings: []
                    )
                ),
            ]
        )
        try structured.write(to: structuredURL)
        let startedAt = Date(timeIntervalSince1970: 100)
        let run = LocalProcessingRun(
            id: "run-1",
            sourcePath: "/tmp/fixture.pdf",
            fileName: "fixture.pdf",
            providerId: "chandra-ocr-2",
            providerName: "Chandra OCR 2",
            executionMode: "local",
            status: "succeeded",
            outputPath: outputURL.path,
            structuredOutputPath: structuredURL.path,
            errorMessage: nil,
            pageCount: 1,
            startedAt: startedAt,
            completedAt: startedAt.addingTimeInterval(1)
        )

        let artifacts = try DesktopClientProjection.artifacts(for: run)

        #expect(artifacts.markdown == "hello")
        #expect(artifacts.blocks.first?.label == "Title")
        #expect(artifacts.blocks.first?.bbox == [125, 250, 375, 750])
        #expect(artifacts.manifest.durationMs == 1_000)
    }
}
