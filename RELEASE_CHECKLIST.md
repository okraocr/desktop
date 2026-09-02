# okraPDF Desktop — Release Checklist

Current train: `desktop-v1.0.0-rc.18`

Roadmap items: `D.6.3`, `Stable #15`, `D.6.9`, `D.6.13`, `D.6.14`, `D.6.15`, `D.6.16`, `D.6.17`, `D.6.18`, `D.6.19`, `D.6.20`, `D.6.21`, `D.6.22`, `D.6.23`, `D.6.24`, `D.6.25`

## Product contract

- [x] Windowed app with native PDFKit preview
- [x] Regular activation policy and Dock lifecycle
- [x] Document-first workspace with a permanent resizable source PDF on the left and Facet output/review surface on the right
- [x] Facet exposes only Parse and Redact task modes
- [x] Optional leading drawer contains Runs only
- [x] Native Settings window owns model choice, active/recommended state, setup, progress, cancellation, and retry
- [x] Native Settings window owns Presidio configuration; Facet setup handoffs open the relevant Settings page
- [x] First-run comparison sheet and workspace plugin catalog are retired
- [x] Native toolbar with the canonical mark, document title, Open, source reveal, extraction-box controls, and workspace navigation toggle
- [x] Facet remains visible while optional navigation is tucked away by default; changing navigation never discards output state
- [x] Navigation transitions honor Reduce Motion and expose accessible labels, help, and selected state
- [x] Hidden navigation controls are disabled and removed from accessibility; the toolbar toggle remains available
- [x] Open and document replacement are disabled and centrally guarded during setup or parsing
- [x] PDF drag-and-drop
- [x] **Open PDF…** picker
- [x] Explicit Parse action; opening/replacing a PDF creates no run
- [x] Chandra OCR 2 selected by default on eligible clean installs; license, setup, and Parse remain explicit
- [x] Dots host gate requires Apple silicon, macOS 14+, 16 GB+ memory, and setup space; incompatible hosts fall back to Apple Vision, and setup separately requires Python 3.10+
- [x] Apple Vision remains available without setup
- [x] Local parser doctor recommends a compatible pairing without downloading or parsing
- [x] Settings keeps host-adaptive recommendation and setup/license consent explicit without auto-downloading
- [x] Auto (Hybrid) native-text reuse with page-local Ollama vision fallback
- [x] Generic Ollama provider with HTTP model discovery and vision-capability filtering
- [x] Ollama model selection persists without inspecting its model directory or invoking its CLI
- [x] Docling provider removed for beta.20
- [x] Optional Baidu Unlimited-OCR remains selectable with its pinned setup/readiness state and lineage copy
- [x] Stored Baidu selection remains selected; interrupted Baidu runs resume only through the Baidu provider
- [x] Native byte-counted Baidu model download with cancel/resume state
- [x] Pinned Baidu model revision and SHA-256 verification before readiness
- [x] Truthfully labeled Baidu Unlimited-OCR simulation mode
- [x] Pinned Dots OCR 1.5 model revision and SHA-256 verification before readiness
- [x] Optional Chandra OCR 2 managed provider pinned to the `mlx-community/chandra-ocr-2-oQ8` 8-bit MLX conversion
- [x] Pinned Chandra model revision and SHA-256 verification of all 9 artifacts before readiness
- [x] Native byte-counted Chandra model download with cancel/resume state
- [x] Chandra model OpenRAIL terms disclosed before setup
- [x] Chandra layout-HTML parsing into labeled typed blocks with normalized source-PDF boxes
- [x] Chandra per-token loop guard halts repeated generation tails; duplicate suppression remains as backstop
- [x] Truthfully labeled Chandra OCR 2 simulation mode
- [x] Chandra OCR 2 is the clean-install extraction default on eligible Macs; saved choices and incompatible-host fallback remain explicit
- [x] Dots model terms disclosed before setup
- [x] Truthfully labeled Dots OCR 1.5 simulation mode
- [x] Streaming progress and local errors
- [x] Canonical per-parser page lifecycle (`idle`, `inProgress`, `done`, `attention`, `error`)
- [x] Lazy page-state strip with parser name, visible text/symbol states, and complete VoiceOver labels
- [x] Passive stall warning after 90 seconds without progress updates
- [x] Low-memory warning while a local run is active
- [x] Cross-instance managed-MLX run queue with a visible waiting state for Dots and Baidu
- [x] In-app Sparkle auto-update: Check for Updates… downloads, verifies, and relaunches into the newest signed beta
- [x] Cancel Run action with persisted cancel intent and terminal canceled state
- [x] Interrupted-run recovery and same-run Resume action
- [x] Atomic page-level Markdown checkpoints for Apple Vision, Dots OCR 1.5, and Baidu Unlimited-OCR
- [x] Dots layout-array decoding and official Qwen smart-resize box normalization
- [x] Typed normalized blocks in per-page and aggregate `result.json`
- [x] Deterministic repeated-tail suppression with diagnostics
- [x] Preview, Markdown, and JSON output modes for Apple Vision, Dots, and Baidu runs
- [x] Source-PDF bounding boxes for valid Dots and Baidu normalized layout blocks
- [x] Apple Vision structured output and source-PDF boxes for native text and scanned OCR observations
- [x] Provider-neutral source-PDF overlays for Apple Vision, Dots OCR 1.5, and Baidu Unlimited-OCR
- [x] Two-way source-box and preview-card selection across zoom, scroll, crop, and rotation
- [x] Two-way source-box and preview-card hover highlighting, including card scroll-into-view
- [x] Accessible Show boxes toolbar toggle; overlays remain screen-only and never mutate the source PDF
- [x] Copy, Save As, and Reveal actions for Markdown and JSON
- [x] Explicit post-parse Presidio PII detection over positioned extraction blocks
- [x] Human approval/exclusion of every candidate with PDFKit source-box review
- [x] Affected-page rasterization and burned black boxes in a new PDF; source remains unchanged
- [x] Optional official Presidio LangExtract recognizer through local Ollama only
- [x] No cloud upload or remote-control surface

## Persistence and privacy

- [x] Source PDFs remain in place
- [x] No account, library database, cloud metadata, policy, spend, or audit records
- [x] Run lifecycle persisted as `run.json` under Application Support
- [x] Pollable progress snapshots and sequenced lifecycle stream persisted as `run.json` and `events.jsonl`
- [x] Parser/page lifecycle matrix persisted in `run.json` with legacy-manifest decoding
- [x] Results stored beside each run manifest as `result.md`
- [x] Apple Vision, Dots, and Baidu structured results stored beside each run manifest as `result.json`
- [x] Recent local runs re-open from Activity in the left navigation
- [x] Dots OCR 1.5 and Baidu Unlimited-OCR inference force Hugging Face/Transformers offline mode
- [x] Provider setup is visibly distinct from offline extraction
- [x] Ollama is represented as a loopback HTTP integration, separate from Okra-managed Dots and Baidu setup
- [x] Presidio installs under its own pinned managed runtime and analyzes only after an explicit Detect action
- [x] Presidio candidate boxes persist beside the run as `redactions.json`; analyzed text is not logged
- [x] Presidio remains the explicit post-parse PII default; CLI detection returns candidates without approving or exporting them

## Automated verification

- [x] Local-processing tests retained
- [x] Simulated Baidu Unlimited-OCR PDF → pages → worker → Markdown + JSON → manifest E2E
- [x] Simulated Dots OCR 1.5 PDF → pages → worker → Markdown + JSON → manifest E2E
- [x] Simulated Chandra OCR 2 PDF → pages → worker → Markdown + JSON → manifest E2E
- [x] Chandra layout-HTML prompt contract, labeled-block parsing, nested-block recovery, box clamping, duplicate-tail suppression, plain-text fallback, and checkpoint provenance coverage
- [x] Dots layout-array parsing, category mapping, malformed-output recovery, table HTML, and pixel-box normalization coverage
- [x] Mid-run `run.json` progress and 120-page checkpoint persistence coverage
- [x] Cancel ordering, orphan recovery, checkpoint resume, and child-process termination coverage
- [x] Lifecycle TDD for transitions, parser isolation, Codable round trips, health attention, cancellation, errors, and completion
- [x] Run-health stall/memory decision logic and cross-process lock queue coverage
- [x] Appcast item insertion, newest-first ordering, and re-run replacement coverage
- [x] Synthetic aToken fixture covers whitespace decoding, malformed markers, normalized boxes, HTML preservation, and repeated-tail suppression
- [x] Provider-neutral PDF overlay adapter, clipping, fixed crop/rotation geometry, annotation ownership, click-selection, and hover-state coverage
- [x] Apple Vision native-text and scanned-observation structured-output coverage
- [x] Default app state constructs every bundled provider without terminating
- [x] Ollama `/api/tags`, `/api/show`, and `/api/chat` request contracts have hermetic unit coverage
- [x] Presidio simulation, loopback-only URL policy, source-block mapping, box persistence, and rasterized export coverage
- [x] Authenticated loopback `okra.client.v1` host is owned by Okra.app and rejects unauthenticated clients
- [x] Signed app bundle includes the thin `okra` CLI with health, catalogs, open, parse, run events/status, artifacts, cancel/resume, and detect commands
- [x] Document-first defaults, source/facet modes, model-settings collections, and Runs-only history have unit coverage
- [x] Packaged app starts with builder-only SwiftPM resources hidden
- [x] Headless release launch gates use a separately identified, Developer ID-signed and notarized copy, while the production app and DMG retain their exact signature, Gatekeeper, staple, and layout checks
- [x] Quarantined notarized beta.8 through beta.15 DMGs start through LaunchServices before publishing (2026-07-28)
- [x] DMG packaging stages an Applications shortcut, embeds a checksummed Finder icon layout without GUI automation, and verifies both from the mounted release image
- [x] Remote-control, dispatch, registry, and model-catalog tests removed
- [x] Docling provider, tests, and Docling-only bundled resources removed for beta.20
- [x] `swift build` on an unrestricted macOS shell (2026-07-28)
- [x] Canonical website mark checksum and packaged-resource coverage
- [x] `swift test` on an unrestricted macOS shell (93 tests passed, 2026-07-29)
- [x] Python output-parser, resume, appcast, and protected-release tests (12/12 passed, 2026-07-29)
- [x] RC.4 brand gate, 12 Python tests, 101 Swift tests across 20 suites, and release build pass on the candidate tree (2026-08-05)
- [x] RC.5 brand gate, 35 Python tests, 122 Swift tests across 22 suites, six projection safety tests, and release build pass on the candidate tree (updated 2026-08-13)
- [x] RC.6 brand gate, 37 Python tests, 122 Swift tests across 22 suites, six projection safety tests, and release build pass on the candidate tree (updated 2026-08-13)
- [x] Chandra real-weight dogfood on a 16 GB Apple-silicon MacBook Air: pinned oQ8 model loads, correct labeled layout HTML, loop guard bounds simple-page latency (2026-08-13)
- [x] Local ad-hoc RC.4 package launches and passes empty, loaded-document, light, dark, and 960-point drawer interaction checks (2026-08-05)
- [x] Packaged-app resource-isolation launch and quarantined local-DMG LaunchServices tests pass against the rebuilt RC.4 package (2/2, 2026-08-05)

### Pre-merge CI gate (stable #15)

`.github/workflows/pr-checks.yml` runs on every pull request and push to
`main` so code checks no longer happen only inside the credentialed release
job.

- Secretless: `permissions: contents: read`; no Developer ID, notarization,
  or Sparkle keys are imported. Signing, notarization, stapling, quarantine,
  packaged-launch, appcast signing, and publishing stay exclusive to
  `notarized-release.yml` on `desktop-v*` tags, and a green PR check never
  publishes or mutates `main`.
- Concurrency cancels superseded runs for the same PR/branch ref so the
  hosted macOS lane is not wasted on stale commits.
- Each run executes `scripts/verify-brand-surface.sh`, the Python unit suite
  (`scripts/tests`), `swift test`, `swift build -c release`, an ad-hoc packaged
  app build, and the app-attached CLI startup smoke.
- Tests stay hermetic: `OKRA_DESKTOP_TEST_TMPDIR` routes test workspaces to
  the runner-temporary root, `TestWorkspace` already isolates `UserDefaults`
  suites per test, and no live provider credentials or network inference are
  required.

#### macOS lane and credential isolation

- PR checks and releases use clean GitHub-hosted Apple-silicon `macos-15`
  images so DiskImages and LaunchServices state cannot leak between runs.
- The release job imports the Developer ID certificate into a randomized
  temporary keychain, notarizes with repository secrets, and removes the
  keychain in an `always()` cleanup step. PR checks remain secretless.
- Required toolchains come from the hosted image plus `actions/setup-python`:
  Xcode/Swift 5.9+, `rg`, and Python 3.12.
- Branch protection: the `macos-checks` job is the required pre-merge check
  for `main`.
- Release appcasts are pushed to a dedicated `automation/appcast-*` branch.
  A maintainer opens that branch as a normal pull request so `macos-checks`
  runs before the signed feed update reaches protected `main`.

## Friend-core manual regression

Run every line below against the exact downloadable prerelease candidate.
Record evidence on its release tracking issue or pull request; do not use
a local build.

- [ ] Launch with navigation hidden; confirm source PDF and Facet are both visible with the source as the larger surface
- [ ] Drag the source/facet divider and toggle navigation; confirm neither action discards document or output state
- [ ] Open Settings → Models during a completed run, close Settings, and confirm the selected provider and Facet output remain intact
- [ ] Hover and select grounded blocks in Facet; confirm the matching source boxes highlight, then hover and select source boxes and confirm Facet scrolls to the block
- [ ] Open a one-page text PDF and confirm no extraction starts until **Parse** is clicked
- [ ] Replace it with a multi-page scanned PDF and again confirm no automatic extraction
- [ ] Parse both documents with Apple Vision
- [ ] Confirm multi-page progress remains visible and the app stays responsive
- [ ] Copy output and paste it into a plain-text editor
- [ ] Use **Save As** and verify the resulting `.md` file
- [ ] Use **Reveal** and verify both the stored output and source PDF locations
- [ ] Repeat the Apple Vision flow with the network disconnected
- [ ] Try one invalid or corrupt input and confirm the app rejects or reports it without crashing

## Broader product regression

These retained checks do not replace the friend-core lines above. Do not mark
the real-provider checks complete from Dots or Baidu simulation.

- [x] Launch and confirm the reader window and canonical green Dock icon appear (2026-07-27)
- [ ] Drop a one-page text PDF and confirm no extraction starts
- [ ] Click Parse and confirm Apple Vision starts
- [ ] Drop a multi-page scanned PDF and confirm progress updates by page
- [ ] Copy the output and paste it into a plain-text editor
- [ ] Save the output to a chosen `.md` path
- [ ] Reveal the stored output and source PDF in Finder
- [ ] Switch provider, rerun, and confirm a new run folder and manifest are created
- [x] Run the labeled Baidu Unlimited-OCR simulation on a multi-page PDF (3 pages, 2026-07-27)
- [ ] Select Baidu boxes from both the PDF and preview on a rotated/cropped dogfood PDF
- [ ] Set up Baidu Unlimited-OCR on a 16 GB Apple-silicon Mac and extract offline
- [ ] Set up the pinned Dots OCR 1.5 model on a clean 16 GB Apple-silicon Mac and record peak memory plus multi-page stability
- [ ] Set up the pinned Chandra OCR 2 model on a clean 16 GB Apple-silicon Mac and record peak memory plus multi-page stability

## Distribution

- [x] GitHub prerelease `desktop-v0.5.0-beta.5` with DMG and SHA-256 asset (2026-07-24)
- [x] GitHub prerelease `desktop-v0.5.0-beta.6` with DMG and SHA-256 asset (2026-07-27)
- [x] GitHub prerelease `desktop-v0.5.0-beta.7` with DMG and SHA-256 asset (2026-07-27)
- [x] GitHub prerelease `desktop-v0.5.0-beta.8` with startup fix, DMG, and SHA-256 asset (2026-07-27)
- [x] GitHub prerelease `desktop-v0.5.0-beta.9` with canonical mark, page checkpoints, DMG, and SHA-256 asset (2026-07-27)
- [x] GitHub prerelease `desktop-v0.5.0-beta.10` with structured Baidu output, DMG, and SHA-256 asset (2026-07-27)
- [x] GitHub prerelease `desktop-v0.5.0-beta.11` with durable cancel/resume, DMG, and SHA-256 asset (2026-07-27)
- [x] GitHub prerelease `desktop-v0.5.0-beta.12` with truthful run health, DMG, and SHA-256 asset (2026-07-28)
- [x] GitHub prerelease `desktop-v0.5.0-beta.13` with beta update awareness, DMG, and SHA-256 asset (2026-07-28)
- [x] GitHub prerelease `desktop-v0.5.0-beta.14` on the public okra-project org with DMG and SHA-256 asset (2026-07-28)
- [x] GitHub prerelease `desktop-v0.5.0-beta.15` under the permanent `okra-project/desktop` name with DMG and SHA-256 asset (2026-07-28)
- [x] GitHub prerelease `desktop-v0.5.0-beta.16` with Sparkle in-app updates, signed appcast feed, DMG, and SHA-256 asset (2026-07-28)
- [x] GitHub prerelease `desktop-v0.5.0-beta.17` with Sparkle click-to-restart E2E proof, DMG, SHA-256 asset, and appcast update (2026-07-28)
- [x] GitHub prerelease `desktop-v0.5.0-beta.18` with Baidu source-PDF bounding boxes, DMG, SHA-256 asset, and appcast update (2026-07-28)
- [x] Sparkle.framework embedded, Developer ID signed, notarized, and stapled with the app
- [x] EdDSA update signing: private key in repo secrets only, public key in the bundle
- [x] Developer ID Application signature for team `449BD89VDV`
- [x] Hardened runtime
- [x] App and DMG accepted by Apple notarization and stapled
- [x] Re-downloaded app and DMG accepted by `spctl` as `Notarized Developer ID`
- [x] Public `desktop-v1.0.0-rc.1` prerelease with DMG and SHA-256 assets (2026-07-29)
- [x] Exact RC.1 passes automated signing, notarization, Gatekeeper, DMG, and quarantine-launch gates (2026-07-29)
- [x] Exact RC.1 is re-downloaded, verified, and installed on this MacBook (2026-07-29)
- [x] Public `desktop-v1.0.0-rc.2` prerelease with generic Ollama HTTP integration (2026-07-29)
- [x] RC.2 appcast branch passes `macos-checks` and merges to protected `main` (2026-07-29)
- [ ] Exact RC.2 is re-downloaded, verified, installed, and dogfooded against local Ollama
- [x] Public `desktop-v1.0.0-rc.3` prerelease with dark-mode source-box visibility fix (2026-08-03)
- [x] RC.3 appcast branch passes `macos-checks` and merges to protected `main` (2026-08-03)
- [ ] Exact RC.3 is re-downloaded, verified, installed, and dark-mode box visibility confirmed
- [x] Public `desktop-v1.0.0-rc.4` prerelease with the D.6.3 document-first workspace (2026-08-05)
- [x] RC.4 appcast branch passes `macos-checks` and merges to protected `main` (PR #69, 2026-08-05)
- [x] Exact RC.4 is re-downloaded and passes checksum, disk-image integrity, Developer ID, hardened-runtime, notarization/stapling, Gatekeeper, embedded version/build, and quarantined LaunchServices checks (2026-08-05)
- [x] Exact signed RC.4 empty, loaded-document, Workspace, and Extract layouts are inspected in light appearance; the identical candidate code passes light, dark, wide, and compact inspection before tag (2026-08-05)
- [ ] Exact RC.4 is installed into Applications and dogfooded in dark appearance
- [x] Public `desktop-v1.0.0-rc.5` prerelease publishes a signed/notarized DMG and SHA-256 asset (2026-08-13)
- [x] RC.5 appcast branch passes `macos-checks` and merges to protected `main` (PR #73, 2026-08-13)
- [x] Exact RC.5 is re-downloaded and passes checksum, disk-image integrity, Developer ID, notarization, embedded version/build checks (2026-08-13)
- [x] Exact RC.5 is installed into Applications on this MacBook (2026-08-13)
- [ ] Friend-equivalent clean-Mac install and Apple Vision extraction recorded on issue #47
- [x] Public `desktop-v1.0.0-rc.6` prerelease publishes a signed/notarized DMG and SHA-256 asset (2026-08-14)
- [x] RC.6 appcast branch passes `macos-checks` and merges to protected `main` (PR #75, 2026-08-14)
- [x] Exact RC.6 is re-downloaded and passes checksum, disk-image integrity, Developer ID, notarization, embedded version/build checks, and is installed into Applications on this MacBook (2026-08-14)
- [x] Public `desktop-v1.0.0-rc.7` prerelease publishes a signed/notarized DMG and SHA-256 asset (2026-08-14)
- [x] RC.7 appcast branch passes `macos-checks` and merges to protected `main` (PR #78, 2026-08-14)
- [ ] Exact RC.7 is re-downloaded and passes checksum, disk-image integrity, Developer ID, notarization, embedded version/build checks, and parser setup-guide dogfood
- [x] Public `desktop-v1.0.0-rc.8` prerelease publishes a signed/notarized DMG and SHA-256 asset (2026-08-17)
- [x] `desktop-v1.0.0-rc.9` release, tag, and appcast entry withdrawn; fix forward under a new immutable candidate (2026-08-20)
- [x] Public `desktop-v1.0.0-rc.10` prerelease publishes a signed/notarized DMG and SHA-256 asset (2026-08-21)
- [x] RC.10 appcast branch passes `macos-checks` and merges to protected `main` (PR #90, 2026-08-21)
- [x] Exact RC.10 DMG is re-downloaded, matches published SHA-256 `78d95961e86bec00148fbcc7976a1109a4417cada476079cf900824363228822`, and passes disk-image integrity verification (2026-08-21)
- [x] RC.10 release workflow passes signing, notarization/stapling, Gatekeeper, packaged launch, DMG integrity, publication, and signed-appcast generation (run `32506090561`, 2026-08-21)
- [x] Public `desktop-v1.0.0-rc.11` prerelease publishes a signed/notarized DMG and SHA-256 asset (2026-08-21)
- [x] RC.11 appcast branch passes `macos-checks` and merges to protected `main` (PR #94, 2026-08-21)
- [x] Exact RC.11 DMG is re-downloaded, matches published SHA-256 `459d957ec384ac485d96c22713d87d24626221f571311abca9ee5e668374f303`, passes disk-image integrity verification, and is accepted as `Notarized Developer ID` (2026-08-21)
- [x] RC.11 release workflow passes signing, notarization/stapling, Gatekeeper, packaged launch, DMG integrity, publication, and signed-appcast generation (run `32519554924`, 2026-08-21)
- [x] Public `desktop-v1.0.0-rc.12` prerelease publishes a signed/notarized DMG and SHA-256 asset (2026-08-22)
- [x] RC.12 appcast branch passes `macos-checks` and merges to protected `main` (PR #105, 2026-08-22)
- [x] Exact RC.12 DMG is re-downloaded, matches published SHA-256 `8c174a3bff9760c9f94e06290bceb293f2c0528d6bceb256b27ecc9bbfee60b8`, passes disk-image integrity and staple validation, and is accepted as `Notarized Developer ID` (2026-08-22)
- [x] RC.12 release workflow passes signing, notarization/stapling, Gatekeeper, packaged launch, DMG integrity, publication, and signed-appcast generation (run `32605739729`, 2026-08-22)
- [x] RC.13 through RC.16 tags produced no public release assets; all four candidates fix forward without moving any immutable tag (2026-08-25)
- [x] Public `desktop-v1.0.0-rc.17` prerelease publishes the signed/notarized source/facet workspace, Chandra OCR 2, Presidio, and bounded local CLI DMG plus SHA-256 asset (2026-08-26)
- [x] RC.17 release workflow passes signing, app/DMG notarization and stapling, quarantined Gatekeeper assessment, disk-image integrity, the production app/CLI health and version handshake, publication, and signed-appcast generation (run `32942521047`, 2026-08-26)
- [x] RC.17 final appcast replacement passes `macos-checks` and merges to protected `main`; PR #144 replaces the superseded artifact entry from PR #142 (2026-08-26)
- [x] Exact RC.17 DMG is independently re-downloaded at 3,538,560 bytes and matches the sidecar and GitHub asset SHA-256 `7690ae1d678275c4ac603caf8a1d9b91472b0985df4a88ae95a7b4060a9cf20a` (2026-08-26)
- [x] Public `desktop-v1.0.0-rc.18` prerelease publishes the D.6.25 action-first Parse/Redact workspace and Settings-owned local model catalog as a signed/notarized DMG plus SHA-256 asset (2026-09-01)
- [x] RC.18 release workflow passes signing, app/DMG notarization and stapling, quarantined Gatekeeper assessment, disk-image integrity, the production app/CLI health and version handshake, publication, and signed-appcast generation (run `33588111376`, 2026-09-01)
- [x] RC.18 signed appcast passes `macos-checks` and merges to protected `main` in PR #147; one unrelated parser-lifecycle timing failure passed on the clean failed-job rerun (run `33588467200`, 2026-09-01)
- [x] Exact RC.18 DMG is independently re-downloaded at 3,423,516 bytes, matches its sidecar SHA-256 `91a1fd8aedec774000d4f9ffd4d9241f9f63b9ce36b9b8f8fd8b2ae8986ca320`, passes disk-image integrity, staple, and quarantined Gatekeeper validation, and completes the production app/CLI health and version handshake (2026-09-01)
- [x] RC.8 appcast branch passes `macos-checks` and merges to protected `main` (PR #80, 2026-08-17)
- [x] Exact RC.8 DMG is re-downloaded and matches published SHA-256 `86559fbb63d6c7f151b603c56a3022095bdba836af76fa9e03fb227e55f60267` (2026-08-17)
- [x] RC.8 release workflow passes disk-image integrity, Developer ID, notarization/stapling, Gatekeeper, embedded build, and quarantined LaunchServices checks (run `32057788576`, 2026-08-17)
- [ ] Exact RC.8 is installed on a release Mac and dogfooded with managed Presidio redaction plus optional Ollama inference
- [ ] Signed in-place **Install and Relaunch** update evidence recorded on issue #39
