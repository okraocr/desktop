# okraPDF Desktop v1.0.0-rc.13

This release makes local automation a first-class companion to the native app.

- Adds a signed, bundled `okra` command-line client. It talks only to the running Okra app, so the app remains the single owner of model processes, documents, runs, and artifacts.
- Adds an authenticated, loopback-only `okra.client.v1` host with health, provider/parser catalogs, read-before-parse document opening, parse runs, event replay, cancel/resume, canonical artifacts, and Presidio detection.
- Makes Chandra OCR 2 the clean-install extraction default on eligible Apple-silicon Macs. Model download and OpenRAIL license acceptance remain explicit in Plugins.
- Keeps Microsoft Presidio as the explicit post-parse PII default. The CLI can request candidate detection, but approval and destructive-looking redaction export remain human-controlled in the app.
- Preserves Apple Vision fallback on incompatible Macs and every saved parser choice.

The CLI is bundled at `/Applications/Okra.app/Contents/Resources/okra`. Link it once with `sudo ln -sf /Applications/Okra.app/Contents/Resources/okra /usr/local/bin/okra`, then use `okra chandra document.pdf` for the default Chandra OCR 2 path or `okra presidio document.pdf` for explicit Presidio candidate detection. It launches or reconnects to Okra.app through an authenticated LaunchServices callback, then talks only to the app-owned loopback service.
