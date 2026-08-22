import AppKit
import Foundation
import PDFKit

struct PDFPageRenderLimits: Equatable, Sendable {
    static let standard = PDFPageRenderLimits(
        maximumPageCount: 2_000,
        maximumRenderedBytes: 4 * 1_024 * 1_024 * 1_024,
        minimumFreeBytes: 1 * 1_024 * 1_024 * 1_024
    )

    let maximumPageCount: Int
    let maximumRenderedBytes: Int64
    let minimumFreeBytes: Int64

    func validate(pageCount: Int) throws {
        guard pageCount <= maximumPageCount else {
            throw LocalProcessingError.pageLimitExceeded(
                pageCount: pageCount,
                maximum: maximumPageCount
            )
        }
    }

    func validate(renderedBytes: Int64, availableBytes: Int64) throws {
        guard renderedBytes <= maximumRenderedBytes else {
            throw LocalProcessingError.renderedPageBudgetExceeded(
                maximumBytes: maximumRenderedBytes
            )
        }
        guard availableBytes >= minimumFreeBytes else {
            throw LocalProcessingError.insufficientDiskSpace(
                minimumFreeBytes: minimumFreeBytes
            )
        }
    }
}

enum PDFPageRenderer {
    static func openDocument(
        at sourceURL: URL,
        limits: PDFPageRenderLimits = .standard
    ) throws -> PDFDocument {
        guard let document = PDFDocument(url: sourceURL) else {
            throw LocalProcessingError.invalidPDF
        }
        guard document.pageCount > 0 else {
            throw LocalProcessingError.noPages
        }
        try limits.validate(pageCount: document.pageCount)
        return document
    }

    static func pageImage(
        from document: PDFDocument,
        at index: Int,
        maxDimension: CGFloat
    ) throws -> CGImage {
        guard let page = document.page(at: index) else {
            throw LocalProcessingError.invalidPDF
        }
        let bounds = page.bounds(for: .cropBox)
        let scale = maxDimension / max(bounds.width, bounds.height)
        let size = NSSize(
            width: max(1, bounds.width * scale),
            height: max(1, bounds.height * scale)
        )
        let image = page.thumbnail(of: size, for: .cropBox)
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            throw LocalProcessingError.invalidPDF
        }
        return cgImage
    }

    static func writePagePNGs(
        from sourceURL: URL,
        to directory: URL,
        maxDimension: CGFloat,
        limits: PDFPageRenderLimits = .standard,
        progress: @escaping LocalProcessingProgress,
        availableCapacity: (URL) throws -> Int64 = availableCapacity(at:),
        fileSize: (URL) throws -> Int64 = fileSize(at:)
    ) throws -> [URL] {
        let document = try openDocument(at: sourceURL, limits: limits)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var renderedBytes: Int64 = 0
        var pageURLs: [URL] = []
        pageURLs.reserveCapacity(document.pageCount)

        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            let url = directory.appendingPathComponent(String(format: "page-%04d.png", index + 1))
            let pageAlreadyExists = FileManager.default.fileExists(atPath: url.path)

            try limits.validate(
                renderedBytes: renderedBytes,
                availableBytes: try availableCapacity(directory)
            )

            if pageAlreadyExists == false {
                try writePagePNGUnchecked(
                    from: document,
                    at: index,
                    to: url,
                    maxDimension: maxDimension
                )
            }

            do {
                renderedBytes += try fileSize(url)
                try limits.validate(
                    renderedBytes: renderedBytes,
                    availableBytes: try availableCapacity(directory)
                )
            } catch {
                if pageAlreadyExists == false {
                    try? FileManager.default.removeItem(at: url)
                }
                throw error
            }

            let fraction = Double(index + 1) / Double(document.pageCount)
            let verb = pageAlreadyExists ? "Using prepared" : "Preparing"
            progress(fraction * 0.2, "\(verb) page \(index + 1) of \(document.pageCount)")
            pageURLs.append(url)
        }

        return pageURLs
    }

    static func writePagePNG(
        from document: PDFDocument,
        at index: Int,
        to url: URL,
        maxDimension: CGFloat,
        limits: PDFPageRenderLimits = .standard,
        availableCapacity: (URL) throws -> Int64 = availableCapacity(at:),
        fileSize: (URL) throws -> Int64 = fileSize(at:)
    ) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let pageAlreadyExists = FileManager.default.fileExists(atPath: url.path)
        try limits.validate(
            renderedBytes: try renderedBytes(in: directory, fileSize: fileSize),
            availableBytes: try availableCapacity(directory)
        )
        guard pageAlreadyExists == false else { return }

        try writePagePNGUnchecked(
            from: document,
            at: index,
            to: url,
            maxDimension: maxDimension
        )
        do {
            try limits.validate(
                renderedBytes: try renderedBytes(in: directory, fileSize: fileSize),
                availableBytes: try availableCapacity(directory)
            )
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private static func writePagePNGUnchecked(
        from document: PDFDocument,
        at index: Int,
        to url: URL,
        maxDimension: CGFloat
    ) throws {
        let image = try pageImage(from: document, at: index, maxDimension: maxDimension)
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw LocalProcessingError.invalidPDF
        }
        try data.write(to: url, options: .atomic)
    }

    private static func renderedBytes(
        in directory: URL,
        fileSize: (URL) throws -> Int64
    ) throws -> Int64 {
        let pageURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return try pageURLs
            .filter { $0.pathExtension.lowercased() == "png" }
            .reduce(into: Int64(0)) { total, pageURL in
                total += try fileSize(pageURL)
            }
    }

    private static func availableCapacity(at directory: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: directory.path)
        guard let bytes = attributes[.systemFreeSize] as? NSNumber else {
            throw LocalProcessingError.diskCapacityUnavailable
        }
        return bytes.int64Value
    }

    private static func fileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let bytes = attributes[.size] as? NSNumber else {
            throw LocalProcessingError.invalidPDF
        }
        return bytes.int64Value
    }
}
