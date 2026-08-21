# okraPDF Desktop v1.0.0-rc.11

> RC.11 separates installable plugins from workspace activity and replaces the
> crowded plugin accordion with focused, grouped left navigation.

## What changed

- Added a compact left-navigation root with two clear sections:
  **Plugins** and **Activity**.
- Kept **Extract** and **Redact** as the only plugins. Their parser, Presidio,
  and optional Ollama setup remains attached to focused plugin destinations.
- Moved **Runs** to **Activity**, where recent local outputs can be reopened and
  the Runs folder can be revealed without pretending history is installable.
- Replaced in-place accordion expansion with one destination at a time and a
  clear Back path to the navigation root.
- Preserved Assistant deep links and `/runs`, while routing Runs as activity
  instead of a plugin and removing the crowded plugin-chip strip.

## Scope and compatibility

- Existing PDFs, run manifests, parser selections, checkpoints, redaction
  candidates, and managed provider environments remain compatible. No
  migration is required.
- Opening or replacing a PDF still never starts parsing or redaction. Downloads
  remain explicit, and installation progress remains coordinator-owned when
  navigation is closed.
- Apple Vision, Dots OCR, Chandra OCR 2, Baidu Unlimited-OCR, and Presidio stay
  local. Ollama remains restricted to its loopback service on this Mac.
- `1.0.0` remains the semantic product version. The immutable
  `desktop-v1.0.0-rc.11` tag identifies this prerelease candidate; it is not a
  stable-release claim.

## Verification

- All 163 Swift tests across 28 suites pass, including navigation boundary and
  Assistant routing coverage.
- All 39 Python packaging and release tests pass.
- The brand-surface gate and `swift build -c release` pass.
- Developer ID signing, hardened runtime, notarization, stapling, Gatekeeper,
  quarantined-DMG launch, and signed-appcast generation run against the exact
  tag before the artifact is published.

## Install

Download `Okra-1.0.0-rc.11.dmg` and its adjacent `.sha256` file from the
[`desktop-v1.0.0-rc.11` GitHub prerelease](https://github.com/okrapdf/desktop/releases/tag/desktop-v1.0.0-rc.11).
Verify the checksum, open the DMG, and drag **Okra** onto the adjacent
**Applications** shortcut. Existing RC installs can take this update in place
through **Check for Updates…** once the signed appcast change is merged.

## Rollback

Reinstall
[`desktop-v1.0.0-rc.10`](https://github.com/okrapdf/desktop/releases/tag/desktop-v1.0.0-rc.10)
from its GitHub prerelease. Run data and managed provider setup are shared, so
no migration is needed in either direction.

## Owner

okraPDF desktop maintainers (`D.6.21`, `okrapdf/desktop`).
