# okraPDF Desktop v1.0.0-rc.9

> RC.9 reshapes the window. The reader is permanent in the center, features
> mount on demand as plugin cards in the trailing assistant panel, and choosing
> a local parser moves out of the run panel into its own dismissible panel on
> the left.

## What changed

- Added the **assistant shell**: the PDF reader stays permanent in the center
  and Extract, Redact, and Runs mount as plugin cards in a trailing panel, with
  a composer that routes `/extract`, `/redact`, and `/runs` — plus plain words —
  through a deterministic on-device router. Nothing in the shell talks to the
  network.
- Added the **Parsers panel** on the leading edge, dismissible from the toolbar
  or its own close button. Every local parser is a row carrying its doctor badge
  and readiness line; the selected row expands in place for its summary, the
  doctor's reason, its Ollama model picker, and any model download still
  outstanding. Setup now happens next to the parser being set up.
- The Extract card is only about the run: the selected parser with a **Change**
  button, Parse or Resume, the per-page lifecycle strip, and output. When the
  selected parser cannot run yet it says why and offers **Open Parsers** instead
  of embedding the setup flow.
- Parser rows keep their descriptor order, so a model finishing its download
  never reshuffles the list under the pointer, and a parser the app has not
  probed is never offered as runnable.
- Removed the provider picker and provider status views from the run panel. The
  first-run setup guide is unchanged.

## Scope and compatibility

- No change to parsing, model pinning, checkpointing, run persistence, bounding
  boxes, or redaction. Existing runs under `~/.okra` remain readable, and a
  parser selection stored by an earlier build is still honored.
- The Parsers panel starts closed so the reader stays dominant. The toolbar
  toggle carries the selected parser's name for VoiceOver.
- Readiness is drawn as an icon plus a label, never color alone.

## Verification

- `swift build` clean and 159 of 159 `swift test` cases pass, including the new
  coverage for parser-row readiness, badges, ordering, and accessibility text.
- Developer ID signing, hardened runtime, notarization, stapling, Gatekeeper,
  and quarantined-DMG checks run in the release workflow before the tagged
  artifact is published.
- This release has not been driven manually on a running window beyond the
  automated packaged-app launch checks.

## Install

Download `Okra-1.0.0-rc.9.dmg` and its adjacent `.sha256` file from the
[`desktop-v1.0.0-rc.9` GitHub prerelease](https://github.com/okrapdf/desktop/releases/tag/desktop-v1.0.0-rc.9).
Verify the checksum, open the DMG, and drag **Okra** onto the adjacent
**Applications** shortcut. Existing RC installs can take this update in place
through **Check for Updates…** once the signed appcast change is merged.

## Rollback

Reinstall
[`desktop-v1.0.0-rc.8`](https://github.com/okrapdf/desktop/releases/tag/desktop-v1.0.0-rc.8)
from its GitHub prerelease. Run data and parser setup are shared, so no
migration is needed in either direction.
