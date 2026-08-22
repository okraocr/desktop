import SwiftUI

struct StructuredExtractionPreview: View {
    let document: StructuredExtractionDocument
    let selectedBlockID: String?
    let hoveredBlockID: String?
    let selectBlock: (String) -> Void
    let hoverBlock: (String, Bool) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: WorkspaceTheme.sectionSpacing) {
            ForEach(document.pages) { page in
                VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Page \(page.pageNumber)")
                            .font(.headline)
                        Spacer()
                        if page.diagnostics.duplicateBlockCount > 0 {
                            Text("\(page.diagnostics.duplicateBlockCount) repeats removed")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if let ungrounded = page.diagnostics.ungroundedBlockCount,
                           ungrounded > 0 {
                            Text("\(ungrounded) without source boxes")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .help("The parser returned these blocks without coordinates, so okraPDF cannot draw overlays for them.")
                        }
                    }

                    ForEach(page.blocks) { block in
                        StructuredExtractionBlockView(
                            block: block,
                            pageNumber: page.pageNumber,
                            isSelected: block.id == selectedBlockID,
                            isHovered: block.id == hoveredBlockID,
                            selectBlock: selectBlock,
                            hoverBlock: hoverBlock
                        )
                        .id(block.id)
                    }
                }

                if page.id != document.pages.last?.id {
                    Divider()
                }
            }
        }
    }
}
