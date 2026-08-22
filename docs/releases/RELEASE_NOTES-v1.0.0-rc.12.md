# okraPDF Desktop v1.0.0-rc.12

> RC.12 preserves Unlimited-OCR structure when the model emits typed markers
> without source coordinates and makes the missing geometry visible in review.

## What changed

- Aligned the bundled Unlimited-OCR parser with the upstream optional-bbox
  marker format. A marker without coordinates now starts a separate typed
  block instead of being absorbed into the preceding grounded block.
- Preserved `bbox: null` for ungrounded blocks, keeping the structured text and
  type without inventing coordinates or a misleading PDF overlay.
- Added grounded and ungrounded block counts to structured diagnostics.
- Added an inspector notice when blocks have no source boxes, with help text
  explaining why those blocks cannot be highlighted on the source PDF.

## Scope and compatibility

- Existing PDFs, run manifests, parser selections, checkpoints, and structured
  outputs remain compatible. The new diagnostic fields are optional when older
  run JSON is decoded.
- Opening or replacing a PDF still never starts parsing. Baidu Unlimited-OCR
  processing stays local, explicit, and source-preserving.
- `1.0.0` remains the semantic product version. The immutable
  `desktop-v1.0.0-rc.12` tag identifies this prerelease candidate; it is not a
  stable-release claim.

## Verification

- All 177 Swift tests across 30 suites pass, including structured-output JSON
  coverage for grounded and ungrounded diagnostic counts.
- All 43 Python packaging and release tests pass, including bbox-less heading,
  text, and table marker regression coverage.
- The brand-surface gate and `swift build -c release` pass.
- Developer ID signing, hardened runtime, notarization, stapling, Gatekeeper,
  quarantined-DMG launch, and signed-appcast generation run against the exact
  tag before the artifact is published.

## Install

Download `Okra-1.0.0-rc.12.dmg` and its adjacent `.sha256` file from the
[`desktop-v1.0.0-rc.12` GitHub prerelease](https://github.com/okrapdf/desktop/releases/tag/desktop-v1.0.0-rc.12).
Verify the checksum, open the DMG, and drag **Okra** onto the adjacent
**Applications** shortcut. Existing RC installs can take this update in place
through **Check for Updates…** once the signed appcast change is merged.

## Rollback

Reinstall
[`desktop-v1.0.0-rc.11`](https://github.com/okrapdf/desktop/releases/tag/desktop-v1.0.0-rc.11)
from its GitHub prerelease. Run data and managed provider setup are shared, so
no migration is needed in either direction.

## Owner

okraPDF desktop maintainers (`D.6.22`, `okrapdf/desktop`).
