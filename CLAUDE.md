# okraPDF Desktop Agent Map

## Source boundary

This repository (`okrapdf/desktop`) is the canonical source of truth for the
desktop app, and it owns public CI, signing, Releases, and the Sparkle
appcast. It was formerly a generated projection of the `steventsao/okra`
monorepo subtree `apps/desktop`; that subtree and its sync tooling were
removed on 2026-08-20, so develop directly here. Product roadmap tracking
(`D.6.x` item IDs) stays in the monorepo's `internal/roadmap.md`. The
monorepo's git history (tag `windows/v0.1.0-alpha.1`) preserves the
unprojected Windows alpha source that lived at `apps/desktop/windows`.

## Product boundary

This app is currently a minimal macOS 13+ windowed PDF reader and local parser. Under
`D.6.20`, the shell is a permanent center reader plus one collapsible trailing
assistant panel where local features mount as plugins (Extract, Redact, Runs)
in a session timeline. The composer routes slash commands and plain words with
a deterministic on-device router — the assistant is **not** a language model
and its copy must never imply one. A collapsible leading Plugins page owns
in-shell dependency setup and progress; Assistant setup handoffs only navigate
there.
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
- `OkraPDF/ContentView.swift` — document-first PDF reader shell, drop target, and the collapsible assistant panel
- `OkraPDF/Assistant/` — assistant panel: plugin registry, deterministic command router, session timeline, and plugin cards
- `OkraPDF/Plugins/` — local plugin catalog, configuration, and coordinator-backed installation progress
- `OkraPDF/Parsers/` — parser choices and setup details embedded in the Extract plugin
- `OkraPDF/Workspace/` — native toolbar, reader surface, and shared panel/theme primitives
- `OkraPDF/PDFReaderView.swift` — native PDFKit reader bridge
- `OkraPDF/LocalProcessing/` — provider contracts, setup, coordinator, and output UI
- `OkraPDF/SetupGuide/` — first-run parser setup guide: ParseBench-style pairing
  combinations, five-dimension radar comparison, filter combo bar, and install
  hand-off into the same coordinator (completed flag:
  `localProcessing.setupGuide.completed`; reopen via Help → Parser Setup Guide…)
- `OkraPDF/ProviderScripts/` — bundled managed-parser setup and worker scripts

## Build and test

```bash
swift build
swift test
```

Do not start a dev server or watch process.

## Product rules

- User-facing brand copy is always `okraPDF`.
- Extraction is local. Only explicit provider setup may download dependencies.
- Opening or replacing a PDF must never start parsing; only the Parse action may run a provider.
- Dots OCR 1.5 is the selected managed default on eligible clean installs, but
  setup and parsing remain explicit. Hardware eligibility requires Apple
  silicon, macOS 14+, and 16 GB+ memory; Apple Vision is the incompatible-host
  and zero-setup fallback. Completing Dots setup requires Python 3.10+.
  Baidu Unlimited-OCR remains an optional selectable legacy provider; preserve
  a stored Baidu selection and resume an interrupted Baidu run only with Baidu.
  Chandra OCR 2 is an optional managed provider (pinned 8-bit MLX, ~5.16 GB)
  with the same explicit setup, host gate, offline inference, and per-run
  provider pinning rules as the other managed parsers.
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
