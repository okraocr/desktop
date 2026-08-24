# okraPDF for Windows

> **Status: unstable alpha.** The unsigned portable `v0.1.0-alpha.2` build is intended
> for testing on Windows 10/11. Expect rough edges; signing, an installer, and
> automatic updates are not wired yet.

Read and parse PDFs privately on your PC — the Windows port of the
[macOS desktop app](..) (SwiftUI + PDFKit).

The product contract is the same as on macOS:

```text
open PDF → read → choose local parser → explicit Parse → readable output
```

Opening a document never starts extraction, the source PDF stays in place,
parsing is explicit, processing stays local, and output is normalized to
`result.md` + `result.json` beside a `run.json` manifest.

## Reader and editor

The Windows shell can keep multiple PDFs open in tabs and compare any two in a
split view. Each document retains its page, zoom, layout, annotation history,
and dirty state. Available layouts are Single Page, Continuous, Two Page, Book,
and Grid.

The navigation panel provides page thumbnails, the PDF outline, full-document
text search with visible highlights, and extraction-run history. PDF text stays
selectable, internal destinations and external links are clickable, and
location back/forward returns through page jumps.

The local edit layer supports text boxes, highlight, underline, strikeout,
freehand drawing, lines, rectangles, ellipses, and PNG/JPEG images. Undo/redo
and crash-recovery drafts are per document. **Save a copy** writes the edits
into a new PDF; it never overwrites the source document.

## Stack

The Windows app mirrors the
[Ollama Windows desktop app](https://github.com/ollama/ollama/tree/main/app):

| Layer    | Ollama / this app                                        |
| -------- | -------------------------------------------------------- |
| Backend  | Go loopback HTTP server (`cmd/okrapdf`, `internal/okra`) |
| Window   | WebView2 via `webview/webview_go` (cgo)                  |
| Frontend | React 19 + Vite 6 + TypeScript + Tailwind 4 (`ui/`)      |
| PDF      | PDF.js inside the WebView (the PDFKit equivalent)        |
| Installer| Inno Setup (planned, not yet wired)                      |

PDF rendering lives in the WebView (PDF.js) rather than in native code; the
Go backend owns run state, providers, artifacts, and dialogs.

## Local parsers

| Parser         | Setup | Notes |
| -------------- | ----- | ----- |
| **Windows OCR** (`windows-ocr`) | None; built into Windows | The Apple Vision equivalent. Uses embedded text (`pdf-text-line` blocks) when a page passes the same quality gate as macOS (24 visible chars), otherwise renders the page and OCRs it with the built-in `Windows.Media.Ocr` WinRT engine (`windows-ocr-line` blocks) through a hidden PowerShell bridge (`internal/okra/ocrbridge.ps1`). The bridge forces UTF-8 stdout: in a no-console child process PowerShell falls back to the OEM codepage (CP437), which rewrites Unicode text (a bullet becomes byte `0x07`) and corrupts JSON. |
| **Chandra OCR 2** (`chandra-ocr-2`) | One-time ~10.6 GB pinned download + managed Python venv | Same client-server contract as macOS: the Go backend (client) spawns a persistent Python worker (server) over loopback HTTP so the 5.3B model loads once per session. `datalab-to/chandra-ocr-2` (torch/transformers; macOS uses the MLX 8-bit build) pinned by revision with SHA-256-verified artifacts, ready-marker runtime lock, offline after setup. **Ollama-style model management:** the download lands in one content-addressed blob store (HF cache layout under `~/.okra/providers/chandra-ocr-2/huggingface`), retries resume incomplete blobs automatically with live GB/% progress, and the model directory is a junction into the snapshot — exactly one copy of the weights, no staging wipe, no manual file management. **Two runtime tracks** (picked automatically at setup): NVIDIA GPU (CUDA 12.6 torch + bitsandbytes 8-bit quantization, comparable to the macOS MLX 8-bit quant; fits an ~8 GB card with fp32 CPU offload) or CPU-only (full bf16; faithful but slow — expect tens of minutes per dense page). `OKRA_DESKTOP_SIMULATE_CHANDRA_OCR=1` exercises the full contract without weights. |
| **Ollama** (`ollama`) | Start Ollama, choose a vision model | Identical contract and prompt to macOS; loopback only (`http://127.0.0.1:11434`). |

The Apple-silicon-only managed parsers on macOS (Dots OCR, Baidu Unlimited-OCR
— MLX-based) are not portable to Windows and are intentionally absent. The
provider contract (`Provider` in `internal/okra/provider.go`) leaves room for
future Windows-native managed parsers.

## Local PII redaction

After a positioned Windows OCR or Chandra run finishes, open the **Redact** tab
to detect PII with Microsoft Presidio, review each candidate box, and export a
new redacted PDF. Detection never starts when a PDF opens, and the source PDF
is never modified.

- **Managed local detector:** the first explicit setup creates
  `~/.okra/providers/presidio/venv`, installs pinned Presidio 2.2.364 plus the
  English spaCy 3.8 model, and runs the analyzer through a session-scoped
  loopback worker. Structured recognizers and spaCy cover values such as
  names, email, phone, SSN, credit cards, locations, IP addresses, and URLs.
- **Optional Ollama enhancement:** enable **Add Presidio's Ollama recognizer**
  and choose an installed local text model. This uses Presidio's official
  experimental `BasicLangExtractRecognizer`/LangExtract integration against
  Ollama on `127.0.0.1:11434`; the documented lightweight default is
  `qwen2.5:1.5b`. Okra never sends detection text to a non-loopback URL.
- **Human review:** v1 maps each detected span to its complete normalized
  extraction block. This intentionally over-redacts instead of risking a
  partial glyph leak; every candidate can be included or excluded before
  export.
- **True removal:** affected pages are rasterized before approved black boxes
  are applied. Unaffected pages are copied as-is. This removes selectable text
  under redactions, at the cost of turning affected pages into images.

For an already-running local Presidio API, set `OKRA_PRESIDIO_URL` to a
loopback URL such as `http://127.0.0.1:3000`. Model selection in the UI is
available only for Okra's managed worker; an external service owns its own
recognizer configuration.

### ParseBench fidelity

The Chandra worker's `OCR_LAYOUT_PROMPT`, label set, bbox scale (0-1000), and
block parsing are **verbatim ports** of the ParseBench pipeline
(`apps/api/packages/chandra-parser-agent/src/prompts.ts`, itself verbatim from
`datalab-to/chandra`) — the same text the macOS worker and the benchmark use.
Sample PDFs equivalent to the ParseBench fixture pages (same documents and
page numbers from public sources, not the gated benchmark files) live in
[`scratch/parsebench-samples/`](../../../scratch/parsebench-samples/) with a
headless API driver (`headless_parse_test.py`).

## Data layout (mirrors macOS)

```text
%APPDATA%\Okra\Runs\<run-id>\run.json            manifest (same fields as macOS)
%APPDATA%\Okra\Runs\<run-id>\events.jsonl        run event ledger
%APPDATA%\Okra\Runs\<run-id>\page-progress.json  checkpoint for cancel/resume
%APPDATA%\Okra\Runs\<run-id>\page-results\page-%04d.json
%APPDATA%\Okra\Runs\<run-id>\pages\page-%04d.png rendered OCR images
%APPDATA%\Okra\Runs\<run-id>\result.md           assembled Markdown
%APPDATA%\Okra\Runs\<run-id>\result.json         StructuredExtractionDocument
                                                 (schemaVersion 1, object "local_extraction")
%APPDATA%\Okra\Runs\<run-id>\redactions.json     latest Presidio candidate boxes
```

`result.json` blocks carry normalized top-left bounding boxes
(`unit: "normalized", origin: "top-left"`) identical to the macOS writers, and
the UI renders them as removable screen-only overlays with two-way
hover/selection against the block list.

## Build

Prerequisites (user-local installs work):

- Go ≥ 1.23 (`%LOCALAPPDATA%\Programs\go`)
- Node.js LTS (`%LOCALAPPDATA%\Programs\node`)
- A gcc toolchain for cgo (`webview_go` requirement; WinLibs mingw-w64 at
  `%LOCALAPPDATA%\Programs\mingw64` is what `scripts\build.ps1` expects)
- WebView2 Runtime at runtime (preinstalled on Windows 10/11 with Edge)
- Python 3.10+ for optional managed Chandra or Presidio setup

One-shot build (UI typecheck + UI build + Go tests + exe):

```powershell
.\scripts\build.ps1
```

Output: `dist\okrapdf.exe` (double-click to run; WebView2 window).

The tagged alpha is distributed as a portable ZIP from the
[GitHub Releases page](https://github.com/steventsao/okra/releases). It is not
code-signed, so Windows SmartScreen may warn before first launch. Verify the
ZIP with the adjacent SHA-256 checksum asset before extracting it.

Manual steps:

```powershell
cd ui; npm install; npm run build; cd ..
go test ./...
go build -ldflags "-H windowsgui" -o dist\okrapdf.exe ./cmd/okrapdf
```

## Run and develop

```powershell
.\dist\okrapdf.exe                  # opens the app window
.\dist\okrapdf.exe C:\docs\spec.pdf # opens a PDF directly (CLI arg, like macOS)
go run ./cmd/okrapdf -serve-only -port 8080  # loopback API only, no window
```

UI development with hot reload (mirrors the Ollama app's `-dev` flow):

```powershell
cd ui; npm run dev                  # Vite on http://localhost:5173
go run ./cmd/okrapdf -dev           # WebView loads the Vite server, devtools on
```

## Test

```powershell
go test ./...        # run lifecycle, normalization, Ollama client, HTTP API
cd ui; npm run typecheck; npm test
```

## Deliberate v1 differences from macOS

- **File picking** uses a hidden-PowerShell `OpenFileDialog` bridge
  (`webview_go` has no dialog API; the Ollama app uses custom per-platform
  dialogs — Inno/native dialogs are a follow-up).
- **Drag-and-drop open** is not wired in v1 (WebView2 drops expose `File`
  objects without paths, which conflicts with the read-in-place contract);
  use Open PDF or the CLI argument.
- **Ollama runs** return Markdown only (no positioned blocks), same as macOS;
  the Blocks and Redact tabs explain this. Parse with Windows OCR or Chandra
  when source-aligned redaction boxes are required.
- The Windows OCR default provider folds the macOS "native text fast path"
  into one provider instead of exposing a separate Hybrid provider.

## License

MIT, same as okraPDF Desktop.
