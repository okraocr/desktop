# Managed provider runtime installation (D.6.26)

RC.18's in-app Baidu setup failed in `python -m venv` because `ensurepip`
initializes Python's MIME database, which reads `/etc/apache2/mime.types`.
App Sandbox denied that read. Granting read-only access to the canonical
`/private/etc/apache2/mime.types` fixes that failure, but does not by itself
make installed runtimes usable.

The sandbox also quarantines native libraries created by pip. On macOS 26.3.1,
the first NumPy import then stalled in dyld signature validation. Installing
the same hash-locked wheels outside the sandbox allowed the sandboxed worker
to import them. A private XPC installation service follows Apple's recommended
[separate service approach](https://developer.apple.com/forums/thread/767612).

## Responsibility and access

- The signed reader stays sandboxed and owns explicit setup, progress, model
  downloads, SHA-256 model verification, readiness, and offline inference.
- The private embedded XPC service owns only dependency installation. It is
  signed with the app's release identity and hardened runtime, without App
  Sandbox. It does not parse PDFs or accept document data.
- Its protocol accepts one built-in provider ID. It accepts no caller-supplied
  command, Python path, environment, download URL, or destination. The service
  chooses the bundled installer and trusted Python independently.
- The service validates the connection's user, live code validity, and host
  executable path against its enclosing app. It derives the destination from
  that signed host's bundle ID and rejects redirected installation paths.
- The existing scripts keep `--require-hashes`, `--only-binary=:all:`, and
  `--require-virtualenv`. Retries clear only the provider's venv. An exclusive
  install lock serializes writes to that provider across connections.
- Cancellation or client disconnect cancels the same process-group runner used
  by the app, including descendants. The helper does not modify system Python,
  disable Gatekeeper, or remove quarantine attributes from existing files.
- Source-only SwiftPM execution retains its direct unsandboxed setup path.
  Packaged apps require the helper and fail visibly if it is missing.

## Verification

The Python suite compiles and signs real sandboxed probe apps using production
entitlements, process environment, XPC client, and helper. It tests clean venv
bootstrap, retry, native library loading from an installed venv, rejection of
unknown provider IDs, and cancellation of an installer with a resistant child.
The XPC probe also uses hardened runtime signing. It requires a supported
Homebrew Python; hosts without one report an explicit test skip.

Local qualification on the M4 Mac mini with Python 3.13 (2026-09-05) additionally
ran the unmodified Baidu/MLX and Presidio installers through the packaged XPC
service. Both installed their complete hash-locked dependency sets. Separate
sandboxed children successfully imported `mlx_vlm` and loaded Presidio's English
spaCy model. No document inference or multi-gigabyte OCR model download was
needed to reproduce and qualify this runtime repair.

The packaged-app test verifies helper presence, its signing role, matching
dependency locks, and the app/CLI launch handshake. Public notarization and
Sparkle distribution remain release gates.
