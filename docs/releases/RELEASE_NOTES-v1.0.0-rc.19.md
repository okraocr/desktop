# okraPDF Desktop v1.0.0-rc.19 — unreleased

Fixes managed model installation in Settings, including the Python `ensurepip`
error shown when installing Baidu Unlimited-OCR.

- Repairs access to the system MIME registry needed by Python's package tools.
- Installs the pinned Python runtime dependencies through a private app helper,
  so macOS permits the installed native libraries to load. This applies to Baidu,
  Dots, Chandra, and Presidio.
- Keeps setup explicit, checks every downloaded dependency against the bundled
  checksum lock, and cancels the installer and its child processes together.

The reader and inference workers remain sandboxed. Model weights still download
only after explicit setup, with the existing pinned-artifact verification.
