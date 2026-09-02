# okraPDF Desktop Agent Map

## Source boundary

This repository (`okrapdf/desktop`) is the canonical source of truth for the
desktop app, and it owns public CI, signing, Releases, and the Sparkle
appcast. It was formerly a generated projection of the `steventsao/okra`
monorepo subtree `apps/desktop`; that subtree and its sync tooling were
removed on 2026-08-20, so develop directly here. Product roadmap tracking
(`D.6.x` item IDs) stays in the monorepo's `internal/roadmap.md`. The Windows
port is canonical in this repository under `windows/`; its first alpha remains
preserved in the monorepo's git history at tag `windows/v0.1.0-alpha.1`.

## Product boundary

The primary app is a minimal macOS 13+ windowed PDF reader and local parser.
The separate `windows/` port uses a Go loopback host, WebView2, React, and
PDF.js while preserving the same read-before-parse and source-preserving rules.
Under `D.6.25`, the shell is a permanent side-by-side workspace: the source PDF
is on the left and the **Facet** output/review surface is on the right. Grounded
extraction blocks and PDFKit bounding boxes share hover and selection state in
both directions. The Facet exposes only **Parse** and **Redact** task modes;
the optional leading drawer is local run history only. Model choice,
host-adaptive recommendation, license/setup, download progress, cancellation,
retry, Ollama discovery, and Presidio configuration live in the native Settings
window. There is no Assistant, plugin catalog, first-run comparison sheet,
composer, command router, or chat surface in the main window.
Do not add per-feature tabs, edge rails, remote control, model-backed chat,
cloud upload, remote registries, promotions, account gates, or backoffice UI.

The supported flow is:

```text
open/drop PDF → read → choose local provider → explicit Parse → readable output
```

## Architecture

- `OkraPDF/App.swift` — normal windowed app lifecycle and File menu command
- `OkraPDF/Support/SparkleUpdaterController.swift` — Sparkle in-app updates (signed appcast, Install and Relaunch)
- `OkraPDF/AppState.swift` — open/drop state separated from explicit parsing
- `OkraPDF/ContentView.swift` — document-first split workspace, drop target, and grouped leading navigation
- `OkraPDF/Settings/` — native settings navigation, local model catalog, active/recommended state, and setup progress
- `OkraPDF/Plugins/` — coordinator-backed Presidio setup content embedded in Settings
- `OkraPDF/Workspace/` — permanent source/facet split, local Runs drawer, native toolbar, reader surface, and shared panel/theme primitives
- `OkraPDF/PDFReaderView.swift` — native PDFKit reader bridge
- `OkraPDF/LocalProcessing/` — provider contracts, setup, coordinator, and output UI
- `OkraPDF/ProviderScripts/` — bundled managed-parser setup and worker scripts
- `windows/` — unsigned Windows alpha source, tests, and portable build script

## Build and test

```bash
swift build
swift test
```

On Windows, run `windows/scripts/build.ps1`; it performs the UI typecheck and
production build, the Go suite, resource generation, and executable build.

Do not start a dev server or watch process.

## Product rules

- User-facing brand copy is always `okraPDF`.
- Extraction is local. Only explicit provider setup may download dependencies.
- Opening or replacing a PDF must never start parsing; only the Parse action may run a provider.
- Chandra OCR 2 is the selected managed default on eligible clean installs, but
  setup and parsing remain explicit. Hardware eligibility requires Apple
  silicon, macOS 14+, and 16 GB+ memory; Apple Vision is the incompatible-host
  and zero-setup fallback. Completing Chandra setup requires Python 3.10+.
  Dots OCR 1.5 remains an optional managed provider.
  Baidu Unlimited-OCR remains an optional selectable legacy provider; preserve
  a stored Baidu selection and resume an interrupted Baidu run only with Baidu.
  Chandra uses a pinned 8-bit MLX model (~5.16 GB) with explicit license,
  setup, host gate, offline inference, and per-run provider pinning.
- The source PDF remains in place; do not reintroduce a copied-file library.
- Successful output is normalized to `result.md` beside a small `run.json` manifest.
  Providers with structured output also write `result.json` with typed blocks and normalized
  top-left layout boxes. Valid boxes render as removable, screen-only PDFKit
  annotations over the source PDF and support two-way selection and hover with
  the block preview; do not expose raw tokenizer artifacts or mutate the source PDF.
- Presidio PII detection is an explicit post-parse action over positioned
  blocks, not a parser or open-time hook. Its managed Python worker and optional
  Ollama recognizer stay on loopback. Human-approved export rasterizes affected
  pages before burning black boxes into a new PDF; never add printable overlay
  annotations that leave the underlying glyphs recoverable.
- Do not add SQLite, cloud fields, policy/spend models, chat, or document agents
  without a new roadmap item and architecture decision.
- Use system controls and accessible SF Symbols only for functional affordances.
