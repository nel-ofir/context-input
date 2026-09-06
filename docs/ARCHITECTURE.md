# Architecture and reliability notes

## Decision pipeline

```text
focused UI element
      │
      ├─ stale/missing and frontmost app declares
      │  terminal-shell support ──────────────► opaque terminal fallback
      │
      ├─ not editable / secure ───────────────► ignore
      │
      ▼
Accessibility text in focused window
      │
      ├─ existing non-empty draft ────────────► classify draft
      │
      └─ nearby text above composer
             │
             └─ nearest usable candidate ─────► classify candidate
                                                    │
                                                    ├─ ambiguous ─► no change
                                                    └─ HE / EN ──► select configured source
```

## Latency

The focus monitor polls at 250 ms and waits 140 ms after a new focused element appears so Electron apps can settle their Accessibility state. Context extraction first climbs from the focused editor to the nearest pane-sized ancestor with substantial content above the composer. This prevents adjacent task lists, chat lists, and document panels from contaminating the open conversation. Candidates must horizontally overlap the composer. Within that pane, extraction walks newest content first with a hard budget of 1,800 Accessibility elements, a maximum depth of 24, and a 250 ms per-application messaging timeout. Classification combines up to 32 nearby nodes while discounting short interface labels, links, filenames, and code-like content. It remains synchronous and local; Unicode script counts are the primary signal, while `NLLanguageRecognizer` supplies a secondary signal for individual mixed-language strings.

## Why Accessibility comes before OCR

Accessibility text has exact characters and layout geometry, works without capturing pixels, and requires only the permission already needed to observe global focus. Screenshot OCR would add Screen Recording permission, more latency, and a second source of Hebrew recognition errors. The reader therefore fails closed when an app hides its text.

GPU-rendered terminals are a narrow exception to the text requirement. When the
frontmost application declares a `Shell` document role or the
`com.apple.terminal.shell-script` content type, an opaque accessibility window
can stand in for a missing or stale focused element. This signal comes from the
application bundle rather than its name. Native text fields and other controls
inside the same application still use the normal classifier.

## Selection verification

Selection request success is distinct from text being entered in the requested
layout. The controller records before/immediate and +250/+650 ms source snapshots.
At +250 ms it makes at most one additional selection if the source differs. There
is no persistent enforcement loop. The
pure `CISwitchVerificationPolicy` covers all combinations of match, check phase,
focus validity, and keyboard activity in unit tests.

Each check validates both the focus generation and decision sequence, the actual
frontmost process and focused AX element, and absence of keyboard/modifier events.
Those events only increment a counter; key contents are not inspected or saved.
Missing activity monitoring cancels the delayed operation. Settings retains the
history when refreshing its current-source label. A verified source is only a
macOS API observation, not proof of a custom renderer's typing behavior.

Opaque terminal detection remains generic and useful for deciding that a focused
terminal should use English. It does not imply that every custom text-input client
will consume a background TIS selection. Warp can retain a different internal
layout even while TIS reports the requested source. Focus-stealing helpers and
synthetic Control-Space/Fn events were tested and removed because they did not
reliably change that internal state. ContextInput makes no app-specific workaround.

## Packaging

ContextInput is a native executable inside a standard `.app` bundle. Sparkle 2 is
embedded as a pinned framework for automatic updates. Language context stays
entirely on-device; Sparkle alone contacts the public GitHub appcast and release
asset URLs.

Local builds use an ad-hoc signature by default. Friend-testable beta releases use
the long-lived `ContextInput Beta Code Signing` self-signed identity. Successive
builds therefore have the same designated requirement (bundle identifier plus
certificate root), which is the prerequisite for retaining the Accessibility
approval across an in-place update. Release ZIPs are additionally signed with a
Sparkle EdDSA key whose private half remains in the release Keychain. A future
Developer ID build can enable hardened runtime and notarization, but moving to
that new identity may cause one final Accessibility reapproval.

## Future hardening

- Replace polling with per-process `AXObserver` focus notifications after profiling missed events across Electron and AppKit apps.
- Add opt-in app adapters for Slack/Teams/Discord accessibility structures.
- Add an optional OCR adapter only when runtime Vision capability checks confirm both `he-IL` and `en-US`; keep it behind a separate Screen Recording permission.
- Replace the self-signed beta certificate with Developer ID signing and
  notarization before broad public distribution.
