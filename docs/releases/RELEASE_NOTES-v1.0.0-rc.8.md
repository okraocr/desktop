# okraPDF Desktop v1.0.0-rc.8

> RC.8 adds explicit local PII redaction with Microsoft Presidio. Detection,
> review, and export remain separate user actions; opening or parsing a PDF
> never starts redaction automatically.

## What changed

- Added a **Redact PII locally** review section beneath structured extraction.
  It maps Presidio findings back to normalized source blocks, shows candidate
  boxes in the existing PDFKit reader, and lets you approve or exclude every
  candidate before export.
- Added explicit managed setup for Microsoft Presidio 2.2.364 and the English
  spaCy 3.8 model under `~/.okra/providers/presidio`. The session worker binds
  only to loopback, does not log analyzed text, and stores the latest candidate
  contract as `redactions.json` beside the local run.
- Added the optional official Presidio LangExtract recognizer through a selected
  installed Ollama model. Ollama remains external to Okra and is contacted only
  at `127.0.0.1:11434`.
- Added irreversible redacted-PDF export. Affected pages are rasterized at 2x
  before approved black boxes are burned in, removing selectable glyphs beneath
  each redaction. Unaffected pages remain normal PDF pages, and the source file
  is never modified.

## Scope and compatibility

- Presidio setup requires Python 3.10 or later and an explicit network download.
  Detection is local after setup.
- Redaction requires a completed parser result with source-aligned boxes. Apple
  Vision, Dots OCR, Baidu Unlimited-OCR, Chandra OCR 2, and positioned Auto
  results are supported; an Ollama-only parse without boxes is not.
- Candidate boxes intentionally cover the complete extraction block containing
  a finding. This over-redacts rather than risking a partial glyph leak.
- This remains a release candidate. There is no cloud upload, account, hidden
  automatic analysis, or mutation of the opened PDF.

## Validation

- Presidio worker unit coverage verifies simulated email, phone, and SSN
  detection plus loopback-only Ollama URLs.
- Swift coverage verifies runtime-marker pinning, worker-to-source-box mapping,
  persisted box JSON, and affected-page rasterized export without source-file
  mutation.
- The complete brand, Python, Swift test, release-build, signing, notarization,
  Gatekeeper, and quarantined-DMG checks run before the tagged artifact is
  published.
- Base Presidio/spaCy uses the pinned managed runtime. The optional experimental
  Ollama recognizer is contract-tested but model-specific quality remains a
  tester responsibility.

## Install

Download `Okra-1.0.0-rc.8.dmg` and its adjacent `.sha256` file from the
[`desktop-v1.0.0-rc.8` GitHub prerelease](https://github.com/okra-project/desktop/releases/tag/desktop-v1.0.0-rc.8).
Verify the checksum, open the DMG, and drag **Okra** onto the adjacent
**Applications** shortcut. The release workflow Developer ID signs, hardens,
notarizes, and staples both the app and DMG. Sparkle also offers the update
in-app after its signed appcast change is reviewed and merged.

## Rollback

RC.7 remains the previous signed candidate. If RC.8 regresses, remove its
appcast item, direct testers to RC.7, and fix forward under a new immutable
release-candidate tag. Existing PDFs, run folders, and managed provider
environments remain untouched.

## Owner

okraPDF desktop maintainers (`D.6.19`, `okra-project/desktop`).
