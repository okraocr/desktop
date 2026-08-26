# okraPDF Desktop v1.0.0-rc.14

This release makes local automation a first-class companion to the native app.

- Adds a signed, bundled `okra` command-line client. It starts or reconnects to Okra.app and talks only to the app-owned local service, so there is one model runtime and one parse history.
- Adds a nonce-authenticated LaunchServices handshake and a bearer-protected, loopback-only `okra.client.v1` host without persisting the bearer token outside the app sandbox.
- Adds PDF-first `okra chandra document.pdf` and `okra presidio document.pdf` commands. PDF access is handed to the sandboxed app through LaunchServices.
- Makes Chandra OCR 2 the clean-install extraction default on eligible Apple-silicon Macs. Model download and OpenRAIL license acceptance remain explicit in Plugins.
- Keeps Microsoft Presidio as the explicit post-parse PII default. Detection returns canonical source-aligned candidates; approval and rasterized redaction export remain human-controlled in the app.
- Preserves Apple Vision fallback on incompatible Macs and every saved parser choice.

The CLI is bundled at `/Applications/Okra.app/Contents/Resources/okra`. Link it once:

```bash
sudo mkdir -p /usr/local/bin
sudo ln -sf /Applications/Okra.app/Contents/Resources/okra /usr/local/bin/okra
```

Then run `okra status`, `okra chandra document.pdf`, or `okra presidio document.pdf`. The reserved RC.13 tag produced no public release; RC.14 is the first published candidate containing this feature and its sandbox/package hardening.
