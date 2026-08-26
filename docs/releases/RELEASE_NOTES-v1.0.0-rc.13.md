# okraPDF Desktop v1.0.0-rc.13

RC.13 makes Chandra OCR 2 the compatible-host clean-install default and ships
a signed thin `okra` CLI that discovers the desktop app through a one-time
LaunchServices callback and talks only to its authenticated loopback host.

- `okra chandra document.pdf` explicitly starts a Chandra parse.
- `okra presidio document.pdf` explicitly parses, then runs Presidio detection.
- Health, catalogs, documents, runs, lifecycle events, artifacts, and redaction
  candidates use the shared `okra.client.v1` wire contract.
- Existing selections and run/setup state remain compatible, and opening a PDF
  still never starts processing.

See the repository-root
[`RELEASE_NOTES-v1.0.0-rc.13.md`](../../RELEASE_NOTES-v1.0.0-rc.13.md) for
verification, installation, rollback, and ownership details.
