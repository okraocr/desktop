# okraPDF Desktop v1.0.0-rc.6

> Fast-follow to RC.5: Chandra OCR 2 runs now stop cleanly at the end of a
> page instead of burning the full token budget on simple documents.

## What changed

- Added a per-token loop guard to the bundled Chandra OCR 2 worker. Greedy
  decoding keeps page output deterministic, but on simple pages the model
  could repeat the same layout block instead of stopping. Generation now
  halts as soon as the same token chunk repeats back to back, and the
  existing duplicate-tail suppression remains as the backstop.
- Real-weight dogfood on a 16 GB MacBook Air (Apple silicon): the pinned
  `mlx-community/chandra-ocr-2-oQ8` model loads through the bundled
  `mlx-vlm==0.6.6` runtime, emits correct labeled layout HTML with
  normalized `data-bbox` anchors, and finishes a simple page in minutes
  instead of tens of minutes with identical extracted content.

## Scope and compatibility

- No default, migration, data-format, or provider-lineup change. Dots OCR
  1.5 remains the managed default on eligible Macs; Chandra OCR 2 remains
  opt-in with the same pinned model revision, hashes, and setup flow
  introduced in RC.5.
- No changes to Apple Vision, Baidu Unlimited-OCR, Auto (Hybrid), or the
  generic Ollama providers.

## Validation

- Brand gate, Python worker suites (including loop-guard unit tests),
  the full Swift test suite, and a production Swift build pass on the
  candidate tree.
- Packaged-artifact launch checks remain reserved for the signed DMG
  workflow.

## Install

Once the release workflow completes, download `Okra-1.0.0-rc.6.dmg` and its
adjacent `.sha256` file from the
[`desktop-v1.0.0-rc.6` GitHub prerelease](https://github.com/okra-project/desktop/releases/tag/desktop-v1.0.0-rc.6).
Verify the checksum, open the DMG, and drag **Okra** onto the adjacent
**Applications** shortcut. At
publication, the app and DMG will be Developer ID signed, hardened, notarized,
and stapled by the release workflow. Sparkle also offers the update in-app.

## Rollback

RC.5 and RC.4 remain available as previous signed candidates. Choosing a
different parser in the parser menu avoids the Chandra worker entirely, and
existing PDFs and local run data remain on disk.

## Owner

okraPDF desktop maintainers (`D.6.17`, `okra-project/desktop`).
