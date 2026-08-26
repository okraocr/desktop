# okraPDF Desktop v1.0.0-rc.13

> RC.13 makes Chandra OCR 2 the compatible-host default and lets terminal
> workflows invoke Chandra and Presidio through the running desktop app.

## What changed

- Chandra OCR 2 is now selected on compatible clean installs. Setup, license
  consent, and parsing remain explicit; existing parser selections are kept.
- The app now owns an authenticated `127.0.0.1` endpoint on a random port. A
  one-time nonce-protected `okra://` LaunchServices callback hands that endpoint
  to the CLI without exposing the app's sandbox or persisting its bearer token.
- The signed app bundles a thin `okra` executable with status, catalog, parse,
  Chandra, detect, and Presidio commands. It starts the app through
  LaunchServices when needed and never loads model weights itself.
- The local endpoint exposes health, providers, parsers, read-before-parse
  documents, runs, lifecycle events, canonical artifacts, and explicit
  Presidio detection results under `okra.client.v1`.
- The app sandbox gains only the server entitlement needed for its loopback
  listener. Requests require the session token and receive no permissive CORS
  headers.

## Scope and compatibility

- Existing PDFs, run manifests, parser selections, checkpoints, setup state,
  and structured outputs remain compatible.
- Opening a PDF still never starts parsing. `okra parse`/`okra chandra` and
  `okra detect`/`okra presidio` are explicit terminal actions.
- `1.0.0` remains the semantic product version. The immutable
  `desktop-v1.0.0-rc.13` tag identifies this prerelease candidate; it is not a
  stable-release claim.

## Verification

- Swift unit and integration coverage includes Chandra default selection,
  read-before-parse routing, canonical artifacts/events, loopback bearer auth,
  endpoint-file permissions, and packaged CLI presence/help.
- Python packaging checks verify the network-server entitlement and nested CLI
  copy/signing steps.
- The brand-surface gate and release build pass before tagging. Developer ID
  signing, hardened runtime, notarization, stapling, Gatekeeper, quarantined-DMG
  launch, and signed-appcast generation run against the exact tag.

## Install and CLI

Download `Okra-1.0.0-rc.13.dmg` and its adjacent `.sha256` file from the
[`desktop-v1.0.0-rc.13` GitHub prerelease](https://github.com/okrapdf/desktop/releases/tag/desktop-v1.0.0-rc.13).
After installing the app, run its bundled command directly or symlink it:

```bash
sudo ln -sf /Applications/Okra.app/Contents/Resources/okra /usr/local/bin/okra
okra chandra document.pdf -o output
okra presidio document.pdf -o pii.json
```

Complete Chandra or Presidio setup in **Plugins** if the CLI reports that a
runtime is not ready.

## Rollback

Reinstall
[`desktop-v1.0.0-rc.12`](https://github.com/okrapdf/desktop/releases/tag/desktop-v1.0.0-rc.12)
from its GitHub prerelease. Run data and managed provider setup are shared, so
no migration is needed in either direction.

## Owner

okraPDF desktop maintainers (`D.6.23`, `okraocr/desktop`).
