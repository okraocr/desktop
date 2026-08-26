# okraPDF Desktop v1.0.0-rc.15

This release makes extracted document structure a permanent companion to the source PDF.

- Replaces the deterministic Assistant/chat panel with a resizable, side-by-side source/facet workspace.
- Keeps the source PDF on the left and extracted blocks, Markdown, JSON, and Presidio review on the right.
- Links grounded extraction blocks and PDF bounding boxes in both directions: hover or select either side to highlight the matching source region or facet block.
- Scrolls the structured block list to the matching block when a source overlay is hovered or selected.
- Reports bbox-less blocks honestly in the structured preview while leaving them readable and non-clickable.
- Keeps parser and Presidio setup in focused Plugins navigation and parse history in Activity → Runs, without a chat composer or slash-command router.
- Preserves explicit Parse and Detect actions, local-only processing, source-in-place reading, and human-approved rasterized redaction export.
- Includes the RC.14 app-owned loopback service and bundled thin `okra` CLI, with Chandra OCR 2 and Presidio as the clean-install defaults for their respective explicit workflows.

The source PDF is never modified, and opening or replacing a document never starts parsing.
