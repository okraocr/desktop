# okraPDF Desktop v1.0.0-rc.16

This release combines the permanent source/facet workspace with app-owned local automation.

- Replaces the deterministic Assistant/chat panel with a resizable workspace that keeps the source PDF beside extracted blocks, Markdown, JSON, and Presidio review.
- Links grounded extraction blocks and PDF bounding boxes in both directions, including hover, selection, and structured-block scroll synchronization.
- Adds a signed, bundled `okra` command-line client. It starts or reconnects to Okra.app and talks only to the app-owned local service, so there is one model runtime and one parse history.
- Uses a nonce-authenticated LaunchServices handshake and a bearer-protected, loopback-only `okra.client.v1` host without persisting the bearer token outside the app sandbox.
- Adds PDF-first `okra chandra document.pdf` and `okra presidio document.pdf` commands. PDF access is handed to the sandboxed app through LaunchServices.
- Makes Chandra OCR 2 the clean-install extraction default on eligible Apple-silicon Macs. Model download and OpenRAIL license acceptance remain explicit in Plugins.
- Keeps Microsoft Presidio as the explicit post-parse PII default. Detection returns canonical source-aligned candidates; approval and rasterized redaction export remain human-controlled in the app.
- Preserves Apple Vision fallback on incompatible Macs, saved parser choices, explicit Parse and Detect actions, and source-in-place reading.
- Hardens the release lane against stale ad-hoc development containers while retaining Developer ID, hardened-runtime, notarization, Gatekeeper, quarantined LaunchServices, and production-DMG checks; mounted installers use the canonical `okraPDF` volume label.

The CLI is bundled at `/Applications/Okra.app/Contents/Resources/okra`. Link it once:

```bash
sudo mkdir -p /usr/local/bin
sudo ln -sf /Applications/Okra.app/Contents/Resources/okra /usr/local/bin/okra
```

Then run `okra status`, `okra chandra document.pdf`, or `okra presidio document.pdf`. The reserved RC.13, RC.14, and RC.15 tags produced no public release assets; RC.16 is the first published candidate containing the app-owned CLI and source/facet workspace.
