import Foundation
import Testing
@testable import Okra

struct StructuredExtractionOutputTests {
    @Test("Structured Unlimited-OCR JSON decodes normalized layout blocks")
    func structuredOutputDecodesNormalizedBlocks() throws {
        let data = try #require(
            """
            {
              "schemaVersion": 1,
              "object": "local_extraction",
              "provider": {"id": "unlimited-ocr", "name": "Baidu Unlimited-OCR"},
              "title": "sample.pdf",
              "pageCount": 1,
              "completedPageCount": 1,
              "complete": true,
              "simulation": false,
              "pages": [{
                "pageNumber": 1,
                "imageFile": "page-0001.png",
                "markdown": "### Deposit form",
                "plainText": "Deposit form",
                "blocks": [{
                  "id": "page-1-block-1",
                  "type": "title",
                  "sourceType": "title",
                  "text": "Deposit form",
                  "bbox": {"x": 0.01, "y": 0.02, "width": 0.29, "height": 0.03, "unit": "normalized", "origin": "top-left"},
                  "sourceBbox": [10, 20, 300, 50],
                  "sourceBboxScale": 1000
                }],
                "diagnostics": {
                  "rawCharacterCount": 100,
                  "decodedCharacterCount": 90,
                  "tokenArtifactCount": 10,
                  "detectionCount": 1,
                  "malformedDetectionCount": 0,
                  "duplicateBlockCount": 0,
                  "loopDetected": false,
                  "groundedBlockCount": 1,
                  "ungroundedBlockCount": 2,
                  "warnings": []
                }
              }]
            }
            """.data(using: .utf8)
        )

        let document = try JSONDecoder().decode(StructuredExtractionDocument.self, from: data)
        let page = try #require(document.pages.first)
        let block = try #require(page.blocks.first)
        let bbox = try #require(block.bbox)

        #expect(document.provider.id == "unlimited-ocr")
        #expect(document.complete)
        #expect(block.type == "title")
        #expect(block.sourceBbox == [10, 20, 300, 50])
        #expect(block.sourceBboxScale == 1000)
        #expect(bbox.width == 0.29)
        #expect(bbox.origin == "top-left")
        #expect(bbox.compactLabel == "x 1% · y 2% · 29% × 3%")
        #expect(page.diagnostics.groundedBlockCount == 1)
        #expect(page.diagnostics.ungroundedBlockCount == 2)
    }

    @Test("Structured table blocks expose readable preview text without changing JSON text")
    func tableBlocksExposeReadablePreviewText() throws {
        let block = StructuredExtractionBlock(
            id: "page-1-block-1",
            type: "table",
            sourceType: "table",
            text: "<table><tr><th>Item</th><th>Total</th></tr><tr><td>Fee</td><td>$49</td></tr></table>",
            bbox: nil,
            sourceBbox: nil,
            sourceBboxScale: nil
        )

        #expect(block.text.contains("<table>"))
        #expect(block.displayText.contains("Item  |  Total"))
        #expect(block.displayText.contains("Fee  |  $49"))
        #expect(block.displayText.contains("<table>") == false)
    }

    @Test("Apple Vision observations become top-left normalized structured blocks")
    func appleVisionObservationsBecomeStructuredBlocks() throws {
        let page = AppleVisionStructuredExtractor.scannedPage(
            from: [
                AppleVisionStructuredExtractor.RecognizedLine(
                    text: "Top line",
                    normalizedBottomLeftBounds: CGRect(
                        x: 0.2,
                        y: 0.7,
                        width: 0.3,
                        height: 0.1
                    )
                ),
                AppleVisionStructuredExtractor.RecognizedLine(
                    text: "Bottom line",
                    normalizedBottomLeftBounds: CGRect(
                        x: 0.1,
                        y: 0.05,
                        width: 0.5,
                        height: 0.08
                    )
                ),
            ],
            pageNumber: 2
        )

        #expect(page.pageNumber == 2)
        #expect(page.markdown == "Top line\nBottom line")
        #expect(page.blocks.map(\.id) == ["page-2-block-1", "page-2-block-2"])
        #expect(page.blocks.allSatisfy { $0.sourceType == "vision-text-observation" })
        #expect(page.blocks.allSatisfy { $0.sourceBboxScale == 1 })

        let topBox = try #require(page.blocks.first?.bbox)
        #expect(abs(topBox.x - 0.2) < 0.000_001)
        #expect(abs(topBox.y - 0.2) < 0.000_001)
        #expect(abs(topBox.width - 0.3) < 0.000_001)
        #expect(abs(topBox.height - 0.1) < 0.000_001)
    }

    @Test("Apple Vision structured documents persist in the shared result shape")
    func appleVisionDocumentRoundTrips() throws {
        let workspace = try TestWorkspace(prefix: "okra-vision-structured")
        try FileManager.default.createDirectory(at: workspace.root, withIntermediateDirectories: true)
        let page = AppleVisionStructuredExtractor.scannedPage(
            from: [
                AppleVisionStructuredExtractor.RecognizedLine(
                    text: "Receipt total",
                    normalizedBottomLeftBounds: CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.1)
                )
            ],
            pageNumber: 1
        )
        let document = StructuredExtractionDocument(
            schemaVersion: 1,
            object: "local_extraction",
            provider: StructuredExtractionProvider(id: "apple-vision", name: "Apple Vision"),
            title: "receipt.pdf",
            pageCount: 1,
            completedPageCount: 1,
            complete: true,
            simulation: false,
            pages: [page]
        )
        let url = workspace.root.appendingPathComponent("result.json")

        try document.write(to: url)
        let restored = try StructuredExtractionDocument.load(from: url)

        #expect(restored == document)
        #expect(restored.pdfBoundingBoxOverlays.map(\.id) == ["page-1-block-1"])
        #expect(restored.pdfBoundingBoxOverlays.first?.providerName == "Apple Vision")
    }
}
