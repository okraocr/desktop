import AppKit
import Foundation
import PDFKit

/// Debug-only screenshot rig for README/PR shell captures.
///
/// Set `OKRA_SHELL_CAPTURE_DIR` to a writable directory and launch a debug
/// build with a PDF argument: the harness waits for the reader to render,
/// drives the assistant through the same `AssistantConversation.send` path a
/// user hits, and renders the app's own window to PNGs — no screen-recording
/// permission involved, and nothing runs in release builds.
enum ShellCaptureHarness {
    @MainActor
    static func startIfRequested(state: AppState) {
        #if DEBUG
        guard let directory = ProcessInfo.processInfo
            .environment["OKRA_SHELL_CAPTURE_DIR"] else {
            return
        }
        let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        log(in: directoryURL, "harness started")

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            state.dismissSetupGuide()
            capture(to: directoryURL, name: "01-reader-assistant.png")

            state.conversation.send(
                "parse the tables in this filing",
                documentIsOpen: state.selectedDocument != nil,
                openPDF: {}
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                capture(to: directoryURL, name: "02-extract-plugin.png")

                state.conversation.send(
                    "redact the PII before I share it",
                    documentIsOpen: state.selectedDocument != nil,
                    openPDF: {}
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    capture(to: directoryURL, name: "03-redact-plugin.png")
                    log(in: directoryURL, "harness finished")
                }
            }
        }
        #endif
    }

    #if DEBUG
    @MainActor
    private static func capture(to directoryURL: URL, name: String) {
        let candidates = NSApp.windows.filter { $0.contentView != nil }
        guard let window = NSApp.keyWindow
            ?? candidates.first(where: \.isVisible)
            ?? candidates.max(by: { $0.frame.width < $1.frame.width }) else {
            log(in: directoryURL, "no capturable window for \(name)")
            return
        }
        guard let contentView = window.contentView else {
            log(in: directoryURL, "no content view for \(name)")
            return
        }
        let frameView = contentView.superview ?? contentView
        let bounds = frameView.bounds
        let scale = window.backingScaleFactor
        let pixelWidth = Int(bounds.width * scale)
        let pixelHeight = Int(bounds.height * scale)
        guard let layer = frameView.layer,
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                      | CGBitmapInfo.byteOrder32Little.rawValue
              ) else {
            log(in: directoryURL, "no layer context for \(name)")
            return
        }
        context.scaleBy(x: scale, y: scale)
        layer.render(in: context)
        drawPDFPages(of: contentView, into: context)
        guard let image = context.makeImage() else {
            log(in: directoryURL, "layer image failed for \(name)")
            return
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            log(in: directoryURL, "png encode failed for \(name)")
            return
        }
        do {
            try data.write(to: directoryURL.appendingPathComponent(name))
            log(in: directoryURL, "wrote \(name)")
        } catch {
            log(in: directoryURL, "write failed for \(name): \(error)")
        }
    }

    /// PDFKit's tile layers do not serialize through `CALayer.render`, so the
    /// page area comes out blank. Redraw the visible pages at the live view's
    /// exact geometry on top of the rendered chrome.
    @MainActor
    private static func drawPDFPages(of contentView: NSView, into context: CGContext) {
        guard let pdfView = findPDFView(in: contentView) else { return }
        let readerRectInWindow = pdfView.convert(pdfView.bounds, to: nil)
        for page in pdfView.visiblePages {
            let cropBox = page.bounds(for: pdfView.displayBox)
            let pageRectInView = pdfView.convert(cropBox, from: page)
            let rectInWindow = pdfView.convert(pageRectInView, to: nil)
            guard rectInWindow.width > 1, cropBox.width > 0, cropBox.height > 0 else {
                continue
            }
            context.saveGState()
            context.clip(to: readerRectInWindow)
            context.setFillColor(.white)
            context.fill(rectInWindow)
            context.translateBy(x: rectInWindow.minX, y: rectInWindow.minY)
            context.scaleBy(
                x: rectInWindow.width / cropBox.width,
                y: rectInWindow.height / cropBox.height
            )
            context.translateBy(x: -cropBox.minX, y: -cropBox.minY)
            page.draw(with: pdfView.displayBox, to: context)
            context.restoreGState()
        }
    }

    @MainActor
    private static func findPDFView(in view: NSView) -> PDFView? {
        if let pdfView = view as? PDFView {
            return pdfView
        }
        for subview in view.subviews {
            if let found = findPDFView(in: subview) {
                return found
            }
        }
        return nil
    }

    private static func log(in directoryURL: URL, _ message: String) {
        let logURL = directoryURL.appendingPathComponent("harness.log")
        let existing = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        try? Data((existing + message + "\n").utf8).write(to: logURL)
    }
    #endif
}
