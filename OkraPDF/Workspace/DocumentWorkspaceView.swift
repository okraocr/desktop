import SwiftUI

struct DocumentWorkspaceView: View {
    let document: LocalPDFDocument?
    let isDropTargeted: Bool
    @ObservedObject var coordinator: LocalProcessingCoordinator
    let canOpenPDF: Bool
    let openPDF: () -> Void
    let openSetupGuide: () -> Void

    var body: some View {
        if let document {
            ZStack {
                PDFDocumentView(
                    url: document.fileURL,
                    overlays: coordinator.pdfBoundingBoxOverlays,
                    showsOverlays: coordinator.showsPDFBoundingBoxes,
                    selectedOverlayID: coordinator.selectedStructuredBlockID,
                    hoveredOverlayID: coordinator.hoveredStructuredBlockID,
                    transientOverlayID: coordinator.previewHoveredStructuredBlockID,
                    onOverlaySelection: coordinator.selectStructuredBlock,
                    onOverlayHover: coordinator.hoverPDFOverlay
                )
                DropTargetOverlayView(isVisible: isDropTargeted)
            }
            .accessibilityLabel("PDF preview for \(document.fileName)")
        } else {
            EmptyDocumentView(
                isDropTargeted: isDropTargeted,
                canOpenPDF: canOpenPDF,
                openPDF: openPDF,
                openSetupGuide: openSetupGuide
            )
        }
    }
}
