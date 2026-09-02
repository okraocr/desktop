+# okraPDF Desktop v1.0.0-rc.18

This release makes the Mac app task-first: the document workspace is for Parse and Redact, while local model management lives in Settings.

- Renames the permanent Facet modes to the two user actions: **Parse** and **Redact**.
- Moves parser choice, host-adaptive recommendation, active state, readiness, license review, model download, progress, cancellation, retry, and Ollama discovery into **Settings → Models**.
- Groups models truthfully as installed or built in, available to download, and unavailable on the current Mac, with search and download sizes where known.
- Keeps healthy defaults: the local parser doctor marks the recommended model for the current Mac, saved choices remain explicit, and incompatible clean installs fall back to Apple Vision.
- Moves Microsoft Presidio installation and optional local Ollama recognizer configuration into **Settings → Redaction**.
- Replaces the former Plugins/Activity navigation with a focused Runs history drawer.
- Retires the first-run parser comparison sheet, so opening the app never interrupts the document workspace with model selection.
- Keeps model downloads, license acceptance, Parse, Redact, candidate approval, and rasterized export explicit. Opening or replacing a PDF still never parses, downloads, detects, or mutates the source automatically.
- Preserves the source/facet hover and selection link, local run persistence, signed bundled `okra` CLI, loopback-only app service, and source-preserving output/export behavior.

The model manager follows Handy's containment pattern—models in a dedicated settings surface—while using okraPDF's own native controls, host diagnosis, privacy rules, and visual language.

