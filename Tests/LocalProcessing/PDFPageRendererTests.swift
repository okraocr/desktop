import AppKit
import Foundation
import PDFKit
import Testing
@testable import Okra

struct PDFPageRendererTests {
    @Test(
        "Page count limit accepts the boundary and rejects the next page",
        .bug("https://github.com/okrapdf/desktop/issues/97")
    )
    func pageCountLimit() throws {
        let limits = PDFPageRenderLimits(
            maximumPageCount: 2,
            maximumRenderedBytes: 100,
            minimumFreeBytes: 10
        )

        try limits.validate(pageCount: 2)
        do {
            try limits.validate(pageCount: 3)
            Issue.record("A PDF above the page limit was accepted")
        } catch LocalProcessingError.pageLimitExceeded(let pageCount, let maximum) {
            #expect(pageCount == 3)
            #expect(maximum == 2)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @MainActor
    @Test(
        "Coordinator rejects oversized documents before creating a run",
        .bug("https://github.com/okrapdf/desktop/issues/97")
    )
    func coordinatorRejectsOversizedDocument() throws {
        let workspace = try TestWorkspace(prefix: "okra-page-limit")
        let document = LocalPDFDocument(
            id: "oversized.pdf",
            fileName: "oversized.pdf",
            filePath: workspace.root.appendingPathComponent("oversized.pdf").path,
            totalPages: PDFPageRenderLimits.standard.maximumPageCount + 1
        )
        let coordinator = LocalProcessingCoordinator(
            providers: [FixtureProcessingProvider()],
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults
        )

        coordinator.run(document: document)

        #expect(coordinator.isRunning == false)
        #expect(coordinator.latestRun == nil)
        #expect(coordinator.statusMessage.contains("supports up to 2000 pages"))
        #expect(FileManager.default.fileExists(atPath: workspace.runsRoot.path) == false)
    }

    @Test(
        "Rendered byte budget and free-space reserve enforce their boundaries",
        .bug("https://github.com/okrapdf/desktop/issues/97")
    )
    func diskBoundaries() throws {
        let limits = PDFPageRenderLimits(
            maximumPageCount: 2,
            maximumRenderedBytes: 100,
            minimumFreeBytes: 10
        )

        try limits.validate(renderedBytes: 100, availableBytes: 10)

        do {
            try limits.validate(renderedBytes: 101, availableBytes: 10)
            Issue.record("A run above the rendered-byte budget was accepted")
        } catch LocalProcessingError.renderedPageBudgetExceeded(let maximumBytes) {
            #expect(maximumBytes == 100)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        do {
            try limits.validate(renderedBytes: 100, availableBytes: 9)
            Issue.record("A run below the free-space reserve was accepted")
        } catch LocalProcessingError.insufficientDiskSpace(let minimumFreeBytes) {
            #expect(minimumFreeBytes == 10)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test(
        "A page that crosses the disk budget is removed",
        .bug("https://github.com/okrapdf/desktop/issues/97")
    )
    @MainActor
    func overBudgetPageIsRemoved() throws {
        let workspace = try TestWorkspace(prefix: "okra-render-budget")
        let sourceURL = workspace.root.appendingPathComponent("source.pdf")
        let outputDirectory = workspace.root.appendingPathComponent("pages", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace.root, withIntermediateDirectories: true)
        let document = PDFDocument()
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        image.unlockFocus()
        document.insert(try #require(PDFPage(image: image)), at: 0)
        try #require(document.write(to: sourceURL))

        do {
            _ = try PDFPageRenderer.writePagePNGs(
                from: sourceURL,
                to: outputDirectory,
                maxDimension: 32,
                limits: PDFPageRenderLimits(
                    maximumPageCount: 1,
                    maximumRenderedBytes: 0,
                    minimumFreeBytes: 0
                ),
                progress: { _, _ in },
                availableCapacity: { _ in Int64.max }
            )
            Issue.record("A rendered page above the byte budget was retained")
        } catch LocalProcessingError.renderedPageBudgetExceeded {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(
            FileManager.default.fileExists(
                atPath: outputDirectory.appendingPathComponent("page-0001.png").path
            ) == false
        )
    }
}
