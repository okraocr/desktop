# okraPDF Desktop v1.0.0-rc.10

> RC.10 keeps the PDF reader permanent, mounts local features in the
> Assistant, and gives plugin installation and configuration a dedicated page
> with progress that continues when the page is closed.

## What changed

- Added the local **Assistant** shell for Extract, Redact, and Runs. Slash
  commands and plain words use a deterministic on-device router; this is not a
  model-backed chat surface and nothing is uploaded.
- Added a dismissible leading **Plugins** page. It is the single place to
  inspect, configure, install, cancel, retry, and continue setup for bundled
  local plugins.
- Moved parser selection and managed parser setup into **Plugins → Extract**.
  The Extract card now links there instead of embedding dependency setup.
- Moved Presidio and optional Ollama recognizer setup into **Plugins → Redact**.
  Assistant only links to the plugin page; Presidio installation progress is
  coordinator-owned and remains visible after closing and reopening it.
- Added explicit Presidio setup phases, determinate progress when available,
  cancellation, retry, and readiness verification.

## Scope and compatibility

- Existing PDFs, run manifests, parser selections, checkpoints, and managed
  provider environments remain compatible. No migration is required.
- Opening or replacing a PDF still never starts parsing or redaction. Downloads
  remain explicit, and Apple Vision remains available without setup.
- Apple Vision, Dots OCR, Chandra OCR 2, Baidu Unlimited-OCR, and Presidio stay
  local. Ollama remains restricted to its loopback service on this Mac.
- RC.9 was withdrawn before this cut. RC.10 is the next immutable candidate and
  the public successor to RC.8.

## Verification

- `swift build` passes.
- All 161 Swift tests across 27 suites pass, including Presidio setup progress
  and cancellation coverage.
- The brand-surface gate and all 39 Python packaging/release tests pass.
- Developer ID signing, hardened runtime, notarization, stapling, Gatekeeper,
  and quarantined-DMG launch checks run in the release workflow before the
  tagged artifact is published.

## Install

Download `Okra-1.0.0-rc.10.dmg` and its adjacent `.sha256` file from the
[`desktop-v1.0.0-rc.10` GitHub prerelease](https://github.com/okrapdf/desktop/releases/tag/desktop-v1.0.0-rc.10).
Verify the checksum, open the DMG, and drag **Okra** onto the adjacent
**Applications** shortcut. Existing RC installs can take this update in place
through **Check for Updates…** once the signed appcast change is merged.

## Rollback

Reinstall
[`desktop-v1.0.0-rc.8`](https://github.com/okrapdf/desktop/releases/tag/desktop-v1.0.0-rc.8)
from its GitHub prerelease. Run data and managed provider setup are shared, so
no migration is needed in either direction.

## Owner

okraPDF desktop maintainers (`D.6.20`, `okrapdf/desktop`).
