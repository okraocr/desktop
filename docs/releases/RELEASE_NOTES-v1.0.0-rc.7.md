# okraPDF Desktop v1.0.0-rc.7

> First run now opens a parser setup guide: every local parser is presented as
> a ParseBench-style pairing and compared on the benchmark's five capability
> dimensions, with a host-adaptive recommendation from the new local parser
> doctor.

## What changed

- **Parser setup guide (D.6.18).** A first-run sheet walks from welcome to
  comparison to explicit setup to done. Every parser is modeled as a pairing —
  pipeline × model — including one pairing per installed Ollama vision model
  for the Ollama and Auto (Hybrid) providers. Each pairing is scored on the
  five ParseBench dimensions (tables, charts, content faithfulness, semantic
  formatting, visual grounding) as relative estimates anchored to public
  benchmark results, drawn on a spider graph with per-dimension bars. A filter
  combo bar narrows pairings by on-device-only, zero-setup, recommended, and
  delivery kind, plus required capabilities like tables or bounding boxes. The
  guide drives the same processing coordinator as the Extract panel, keeps
  setup and license consent explicit, and never downloads or parses on its
  own. Reopen it anytime via Help → Parser Setup Guide… or the empty state.
- **Local parser doctor (D.6.16).** The app now diagnoses which parser fits
  each Mac before any download starts: chip identity and memory-bandwidth
  class, the real GPU-wired model budget, thermal state, and Low Power Mode
  feed a deterministic rule engine that emits explainable verdicts with badges
  (Recommended for this Mac / Fastest / Highest quality). The recommendation
  tunes clean-install default selection, shows in the picker, overlays the
  setup guide's comparison chart, and is copyable as a privacy-safe report via
  Help → Copy Local Parser Diagnostics.

## Scope and compatibility

- No provider-lineup change. Chandra OCR 2, Dots OCR 1.5, Baidu Unlimited-OCR,
  Apple Vision, Auto (Hybrid), and the generic Ollama provider keep their
  pinned models, setup flows, and stored selections.
- The doctor and the setup guide are advisory surfaces: no automatic
  downloads, no automatic parsing, and no changes to run formats, checkpoints,
  or the read-before-parse contract.

## Validation

- Brand gate, the full Swift test suite (including doctor and setup-guide
  catalog/filter coverage), and a production Swift build pass on the candidate
  tree.
- Packaged-artifact launch checks remain reserved for the signed DMG workflow.

## Install

Download `Okra-1.0.0-rc.7.dmg` and its adjacent `.sha256` file from the
[`desktop-v1.0.0-rc.7` GitHub prerelease](https://github.com/okra-project/desktop/releases/tag/desktop-v1.0.0-rc.7).
