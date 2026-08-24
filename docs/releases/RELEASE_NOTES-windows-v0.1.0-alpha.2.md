# okraPDF for Windows v0.1.0-alpha.2

> **Status: unstable alpha prerelease, 2026-08-24.** This is an unsigned
> portable build for technical testers. It is not a stable or broadly
> supported Windows release.

## What is new

- Keep multiple PDFs open in tabs and compare two documents in a split view.
  Page, zoom, layout, annotation history, and dirty state remain isolated per
  document.
- Switch among Single Page, Continuous, Two Page, Book, and Grid layouts.
- Navigate with page thumbnails, the PDF outline, full-document text search
  and visible match highlights, selectable text, PDF links, and location
  back/forward history.
- Add text boxes, highlights, underlines, strikeouts, freehand drawing, lines,
  rectangles, ellipses, and PNG/JPEG images.
- Undo, redo, and recover an unsaved edit draft independently for each open
  document. **Save a Copy** writes the supported annotations into a new PDF and
  never overwrites the source.
- Continue to parse explicitly with Windows OCR, managed Chandra OCR 2, or a
  local Ollama vision model, and retain the local Presidio review/export flow.

## Install

1. Download `okraPDF-Windows-v0.1.0-alpha.2.zip` and the adjacent
   `.sha256` file from the GitHub prerelease.
2. Run `CertUtil -hashfile okraPDF-Windows-v0.1.0-alpha.2.zip SHA256` and
   compare it with
   `FD13F2F1C93875C83EEE043FB504A0DA847FC069DCC581EBFE355FBDA620F2B7`.
3. Unzip the archive and run `okrapdf.exe`. Windows SmartScreen may warn
   because the executable is not code-signed.

## Known alpha gaps

- No installer, code signing, automatic updates, drag-and-drop open, or stable
  support promise.
- The new editor shell has passed focused automated coverage and a local launch
  smoke, but not a clean-machine tester sweep. Keep original PDFs available.
- Save a Copy writes the supported annotation layer; this alpha is not a
  general-purpose PDF object, form, or page-structure editor.
- Ollama parser output does not provide positioned blocks, so Windows OCR or
  Chandra is required for source-aligned redaction boxes.

## Validation

- UI TypeScript typecheck and production build.
- Eight focused document-shell/editor tests, including valid PDF serialization
  for every annotation kind, per-document undo/redo, and recovery drafts.
- Full Go test suite and one-shot Windows executable build.
- Responsive local Windows launch with a PDF fixture; source-preserving Save a
  Copy API coverage.

## Rollout and rollback

Publish annotated tag `windows-v0.1.0-alpha.2` as a GitHub prerelease with the
portable ZIP and SHA-256 asset. This Windows release is separate from the
signed macOS `desktop-v*` Sparkle update feed. If a release-blocking problem is
found, withdraw the prerelease assets and fix forward under a new immutable
alpha tag; do not move or reuse this tag. Existing PDFs and local run/provider
data remain untouched.
