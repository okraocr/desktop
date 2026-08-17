import AppKit
import Foundation
import PDFKit

enum RedactedPDFExporter {
    static func export(
        sourceURL: URL,
        destinationURL: URL,
        boxes: [RedactionBox]
    ) throws {
        guard boxes.isEmpty == false else {
            throw RedactedPDFExportError.noApprovedBoxes
        }
        guard let output = PDFDocument(url: sourceURL), output.pageCount > 0 else {
            throw RedactedPDFExportError.invalidPDF
        }

        let boxesByPage = Dictionary(grouping: boxes, by: \RedactionBox.page)
        for pageNumber in boxesByPage.keys.sorted() {
            let pageIndex = pageNumber - 1
            guard pageIndex >= 0,
                  pageIndex < output.pageCount,
                  let page = output.page(at: pageIndex),
                  let pageBoxes = boxesByPage[pageNumber] else {
                continue
            }
            let rasterized = try rasterizedPage(page, boxes: pageBoxes)
            output.removePage(at: pageIndex)
            output.insert(rasterized, at: pageIndex)
        }

        guard let data = output.dataRepresentation() else {
            throw RedactedPDFExportError.couldNotSerialize
        }
        try data.write(to: destinationURL, options: .atomic)
    }

    private static func rasterizedPage(
        _ page: PDFPage,
        boxes: [RedactionBox]
    ) throws -> PDFPage {
        let pageBounds = page.bounds(for: .cropBox)
        let displayBounds = pageBounds.applying(page.transform(for: .cropBox)).standardized
        guard displayBounds.width > 0, displayBounds.height > 0 else {
            throw RedactedPDFExportError.invalidPage
        }

        let maximumDimension: CGFloat = 8_192
        let requestedScale: CGFloat = 2
        let scale = min(
            requestedScale,
            maximumDimension / max(displayBounds.width, displayBounds.height)
        )
        let pixelWidth = max(1, Int(ceil(displayBounds.width * scale)))
        let pixelHeight = max(1, Int(ceil(displayBounds.height * scale)))
        let pixelSize = NSSize(width: pixelWidth, height: pixelHeight)
        let thumbnail = page.thumbnail(of: pixelSize, for: .cropBox)

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw RedactedPDFExportError.couldNotRasterize
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(origin: .zero, size: pixelSize).fill()
        thumbnail.draw(
            in: NSRect(origin: .zero, size: pixelSize),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSColor.black.setFill()
        for box in boxes {
            guard let normalized = box.boundingBox.clippedNormalizedRect else { continue }
            let x = max(0, (normalized.minX * CGFloat(pixelWidth)) - 2)
            let y = max(0, ((1 - normalized.maxY) * CGFloat(pixelHeight)) - 2)
            let maxX = min(CGFloat(pixelWidth), (normalized.maxX * CGFloat(pixelWidth)) + 2)
            let maxY = min(
                CGFloat(pixelHeight),
                ((1 - normalized.minY) * CGFloat(pixelHeight)) + 2
            )
            NSRect(x: x, y: y, width: maxX - x, height: maxY - y).fill()
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]),
              let image = NSImage(data: png) else {
            throw RedactedPDFExportError.couldNotRasterize
        }
        image.size = displayBounds.size
        guard let result = PDFPage(image: image) else {
            throw RedactedPDFExportError.couldNotRasterize
        }
        let outputBounds = CGRect(origin: .zero, size: displayBounds.size)
        result.setBounds(outputBounds, for: .mediaBox)
        result.setBounds(outputBounds, for: .cropBox)
        return result
    }
}

enum RedactedPDFExportError: LocalizedError {
    case noApprovedBoxes
    case invalidPDF
    case invalidPage
    case couldNotRasterize
    case couldNotSerialize

    var errorDescription: String? {
        switch self {
        case .noApprovedBoxes:
            return "Approve at least one redaction before exporting."
        case .invalidPDF:
            return "The source PDF could not be opened."
        case .invalidPage:
            return "A page has invalid bounds and could not be redacted."
        case .couldNotRasterize:
            return "A redacted page could not be rendered safely."
        case .couldNotSerialize:
            return "The redacted PDF could not be created."
        }
    }
}
