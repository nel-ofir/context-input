# ContextInput

ContextInput is a self-contained macOS menu-bar app that chooses a Hebrew or English keyboard when a text field gains focus. It reads nearby visible text through the macOS Accessibility API, makes the decision entirely on-device, and changes the selected keyboard input source through macOS Text Input Source Services.

No context, screenshots, analytics, or model requests leave the Mac. The updater
contacts only this project's public GitHub feed to check versions and download a
cryptographically signed release.

## Why this uses Apple Natural Language—not a generative LLM

The task is language identification, not text generation. Hebrew and English normally use distinct scripts, so a small deterministic script classifier is faster and more dependable than prompting a large model. ContextInput combines that signal with Apple's built-in `NLLanguageRecognizer`, constrained to Hebrew and English.

Apple's Foundation Models framework is deliberately not a runtime dependency:

- The public framework requires macOS 26 and an Apple Intelligence-capable Mac.
- Apple Intelligence must be enabled and its model downloaded.
- Apple's current Apple Intelligence language list does not include Hebrew.
- Generative inference would add latency and nondeterminism to a two-label classification task.

The chosen classifier is local, available on both Intel and Apple Silicon Macs supported by macOS 13+, and normally completes in a few milliseconds.

## Behavior

When focus moves to a normal editable text field, ContextInput:

1. Ignores password/secure fields.
2. Uses an existing draft first, so returning to a partially written reply keeps its language.
   URL- or email-only values are classified from their own Latin characters, so Safari's address bar selects English even on a Hebrew page.
3. Reads recent visible conversation text in the focused window.
4. Ranks text immediately above and horizontally near the focused field.
5. Combines the recent messages, prioritizing substantive text and discounting short controls, URLs, filenames, and code-like content.
6. Selects the configured Hebrew or English keyboard only when the decision is confident.
7. Checks the reported source after 250 ms and 650 ms. It makes at most one delayed
   retry if the source differs. Keyboard
   activity or a focus change cancels that retry. Settings preserves this history
   separately from its current-source display; real typing is the acceptance test.

If an app does not expose readable Accessibility text, or the evidence is only emoji/punctuation, ContextInput does nothing. This fail-safe avoids disruptive guesses.

Interactive terminals are detected through their accessibility role, editable value, xterm/terminal metadata, and declared shell-document capabilities. For GPU-rendered terminal apps that expose only an opaque window—or leave another app's focused element registered—ContextInput uses the frontmost terminal-capable application as a bounded fallback. Terminal content is classified when exposed; otherwise a focused terminal safely defaults to English.

Window/application announcements are not drafts. App activation also triggers a
new focus evaluation, even if an opaque window has the same Accessibility identity.
To cancel delayed retries, a local event monitor observes only that keyboard or
modifier activity occurred; it never reads or stores key characters or key codes.

Known limitation: custom remote text-input clients such as Warp can keep using a
different layout after macOS reports that the requested source was selected.
ContextInput records this accurately but does not synthesize shortcuts or steal
focus to work around it; those approaches are unreliable and can cause visible UI
side effects. Manual input-source switching continues to work normally.

## Requirements

- An Apple silicon Mac running macOS 13 Ventura or newer
- A Hebrew and an English input source added in System Settings
- Accessibility permission for ContextInput
- Apple Command Line Tools or Xcode to build

## Build and install

Build the Apple silicon app from Terminal:

```sh
./scripts/build-app.sh
```

The result is `dist/ContextInput.app`. For a drag-to-Applications disk image:

```sh
./scripts/build-dmg.sh
```

For a private local build, the scripts apply an ad-hoc signature. To create the
free, friend-testable beta build with a stable identity and automatic updates:

```sh
./scripts/setup-beta-signing.sh   # once on the release Mac
./scripts/package-beta.sh
```

This creates both `dist/releases/ContextInput-0.2.2-arm64.dmg` for installation
and a signed ZIP used by the automatic updater. See
[`docs/RELEASING.md`](docs/RELEASING.md) before publishing the GitHub release.

The beta certificate is self-signed, so macOS will not treat it like an Apple
Developer ID. On first installation, a friend may need to Control-click the app,
choose **Open**, and confirm. They grant Accessibility after the app is in
Applications. Later Sparkle updates are installed in place with the same app
identity, so that permission is expected to remain approved.

For public distribution with a paid Apple Developer account, sign with Developer ID:

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-dmg.sh
```

Then notarize and staple the disk image using your Apple Developer credentials before sharing it. A stable Developer ID signature is important because macOS ties Accessibility approval to the signed app identity.

An ad-hoc or self-signed beta is not notarized. A Developer ID-signed and
notarized release opens normally for other users. Switching the beta channel from
the self-signed identity to Developer ID later will probably require testers to
approve Accessibility one more time.

## First launch

1. Move `ContextInput.app` to Applications and open it.
2. Allow Accessibility access when prompted. If needed, enable it in System Settings → Privacy & Security → Accessibility, then reopen ContextInput.
3. Choose the desired English and Hebrew keyboards in ContextInput Settings.
4. Optionally enable Launch at Login.

The app lives in the menu bar as **אA** and has no Dock icon.

The Settings window displays the exact app version and build number. Close it
with the red window button or the standard **Command-W** shortcut; ContextInput
continues watching from the menu bar.

Automatic update checks run every six hours. **Check for Updates…** is available
from both the menu-bar menu and Settings. Update archives must carry a valid
Sparkle EdDSA signature, and successive apps must keep the same code-signing
identity.

## Current scope and limitations

- Slack, browsers, and Electron apps usually expose enough Accessibility text, but results depend on each app's accessibility implementation.
- The current version does not take screenshots. An OCR fallback would require the broader Screen Recording permission, and should only be added after testing Hebrew recognition on every supported macOS release.
- Context ranking is intentionally generic. App-specific adapters can improve precision for products whose accessibility trees are unusual.
- The app is intentionally not sandboxed; global assistive access and input-source control are poor fits for a Mac App Store sandbox. The free beta uses a stable self-signed identity; Developer ID remains the production-grade path.

## Tests

```sh
./scripts/test.sh
```

Classifier tests cover Hebrew, English, mixed URL content, draft precedence, conversation aggregation around misleading UI text, and ambiguous emoji-only content. A read-only system smoke test also verifies keyboard discovery and the active input source.

The suite also covers all 32 delayed-verification policy combinations and excludes
window announcements from drafts. Run `zsh scripts/test-settings.sh` on macOS to
check that long switch diagnostics fit the scrollable Settings view. This test
does not start focus monitoring or switch keyboards. Neither test proves Warp's
actual typing layout; follow [the manual checklist](docs/TESTING.md).

## Project layout

- `CIAccessibilityContextReader.m` — focused field detection and nearby visible text ranking
- `CIApplicationCapabilities.m` — generic application capability detection for opaque terminal surfaces
- `CILanguageClassifier.m` — script classifier plus Apple's local Natural Language model
- `CIInputSourceManager.m` — keyboard discovery and switching
- `CIAppController.m` — focus debounce, settings, startup, diagnostics, and orchestration
- `scripts/` — app builds, beta signing, DMG/ZIP packaging, update-feed generation, and identity verification

## Apple API references

- [Natural Language language recognition](https://developer.apple.com/documentation/naturallanguage/nllanguagerecognizer)
- [Natural Language Hebrew identifier](https://developer.apple.com/documentation/naturallanguage/nllanguage/hebrew)
- [Foundation Models system model availability](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
- [Apple Intelligence device and language requirements](https://support.apple.com/en-il/121115)
- [macOS Accessibility elements](https://developer.apple.com/documentation/applicationservices/axuielement)

## Third-party software

Automatic updates use [Sparkle](https://sparkle-project.org/) 2.9.6 under its
permissive license. The exact release archive is checksum-pinned by
`scripts/fetch-sparkle.sh`, and its license is bundled in the app.
