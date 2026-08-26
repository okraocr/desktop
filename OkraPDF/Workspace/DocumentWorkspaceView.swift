import SwiftUI

struct DocumentWorkspaceView: View {
    let document: LocalPDFDocument?
    let isDropTargeted: Bool
    let facetMode: FacetWorkspaceMode
    @ObservedObject var coordinator: LocalProcessingCoordinator
    @ObservedObject var redaction: PresidioRedactionCoordinator
    let canOpenPDF: Bool
    let openPDF: () -> Void
    let openSetupGuide: () -> Void

    var body: some View {
        if let document {
            ZStack {
                PDFDocumentView(
                    url: document.fileURL,
                    overlays: activeOverlays,
                    showsOverlays: coordinator.showsPDFBoundingBoxes,
                    selectedOverlayID: activeSelectedOverlayID,
                    hoveredOverlayID: activeHoveredOverlayID,
                    transientOverlayID: activeTransientOverlayID,
                    onOverlaySelection: selectOverlay,
                    onOverlayHover: hoverOverlay
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

    private var reviewingRedactions: Bool {
        facetMode == .redaction && redaction.detection != nil
    }

    private var activeOverlays: [PDFBoundingBoxOverlay] {
        reviewingRedactions ? redaction.pdfOverlays : coordinator.pdfBoundingBoxOverlays
    }

    private var activeSelectedOverlayID: String? {
        reviewingRedactions ? redaction.selectedBoxID : coordinator.selectedStructuredBlockID
    }

    private var activeHoveredOverlayID: String? {
        reviewingRedactions ? redaction.hoveredBoxID : coordinator.hoveredStructuredBlockID
    }

    private var activeTransientOverlayID: String? {
        reviewingRedactions ? redaction.hoveredBoxID : coordinator.previewHoveredStructuredBlockID
    }

    private func selectOverlay(_ id: String) {
        if reviewingRedactions {
            redaction.selectBox(id)
        } else {
            coordinator.selectStructuredBlock(id)
        }
    }

    private func hoverOverlay(_ id: String?) {
        if reviewingRedactions {
            redaction.hoverPDFOverlay(id)
        } else {
            coordinator.hoverPDFOverlay(id)
        }
    }
}
