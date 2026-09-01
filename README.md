# ContextInput

ContextInput is a self-contained macOS menu-bar app that chooses a Hebrew or English keyboard when a text field gains focus. It reads nearby visible text through the macOS Accessibility API, makes the decision entirely on-device, and changes the selected keyboard input source through macOS Text Input Source Services.

No context, screenshots, analytics, or model requests leave the Mac.

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

If an app does not expose readable Accessibility text, or the evidence is only emoji/punctuation, ContextInput does nothing. This fail-safe avoids disruptive guesses.

Interactive terminals are detected through their accessibility role, editable value, and xterm/terminal metadata. Terminal content is classified when exposed; otherwise a focused terminal safely defaults to English.

## Requirements

- macOS 13 Ventura or newer
- A Hebrew and an English input source added in System Settings
- Accessibility permission for ContextInput
- Apple Command Line Tools or Xcode to build

## Build and install

Build a universal Apple Silicon + Intel app from Terminal:

```sh
./scripts/build-app.sh
```

The result is `dist/ContextInput.app`. For a drag-to-Applications disk image:

```sh
./scripts/build-dmg.sh
```

For a private local build, the scripts apply an ad-hoc signature. For distribution, sign with Developer ID:

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-dmg.sh
```

Then notarize and staple the disk image using your Apple Developer credentials before sharing it. A stable Developer ID signature is important because macOS ties Accessibility approval to the signed app identity.

An ad-hoc local build is not notarized. On first launch, macOS may require Control-clicking the app and choosing **Open**. A Developer ID-signed and notarized release opens normally for other users.

## First launch

1. Move `ContextInput.app` to Applications and open it.
2. Allow Accessibility access when prompted. If needed, enable it in System Settings → Privacy & Security → Accessibility, then reopen ContextInput.
3. Choose the desired English and Hebrew keyboards in ContextInput Settings.
4. Optionally enable Launch at Login.

The app lives in the menu bar as **אA** and has no Dock icon.

The Settings window displays the exact app version and build number. Close it
with the red window button or the standard **Command-W** shortcut; ContextInput
continues watching from the menu bar.

## Current scope and limitations

- Slack, browsers, and Electron apps usually expose enough Accessibility text, but results depend on each app's accessibility implementation.
- The current version does not take screenshots. An OCR fallback would require the broader Screen Recording permission, and should only be added after testing Hebrew recognition on every supported macOS release.
- Context ranking is intentionally generic. App-specific adapters can improve precision for products whose accessibility trees are unusual.
- The app is intentionally not sandboxed; global assistive access and input-source control are poor fits for a Mac App Store sandbox. Developer ID distribution is the practical path.

## Tests

```sh
./scripts/test.sh
```

Classifier tests cover Hebrew, English, mixed URL content, draft precedence, conversation aggregation around misleading UI text, and ambiguous emoji-only content. A read-only system smoke test also verifies keyboard discovery and the active input source.

## Project layout

- `CIAccessibilityContextReader.m` — focused field detection and nearby visible text ranking
- `CILanguageClassifier.m` — script classifier plus Apple's local Natural Language model
- `CIInputSourceManager.m` — keyboard discovery and switching
- `CIAppController.m` — focus debounce, settings, startup, diagnostics, and orchestration
- `scripts/` — self-contained `.app` and `.dmg` packaging

## Apple API references

- [Natural Language language recognition](https://developer.apple.com/documentation/naturallanguage/nllanguagerecognizer)
- [Natural Language Hebrew identifier](https://developer.apple.com/documentation/naturallanguage/nllanguage/hebrew)
- [Foundation Models system model availability](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
- [Apple Intelligence device and language requirements](https://support.apple.com/en-il/121115)
- [macOS Accessibility elements](https://developer.apple.com/documentation/applicationservices/axuielement)
