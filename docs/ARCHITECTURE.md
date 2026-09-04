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

## Packaging

ContextInput is a single native executable inside a standard `.app` bundle. It has no network or third-party runtime dependency. The packaging script creates an ad-hoc signed local bundle by default, or a hardened Developer ID-signed bundle when `SIGNING_IDENTITY` is supplied.

## Future hardening

- Replace polling with per-process `AXObserver` focus notifications after profiling missed events across Electron and AppKit apps.
- Add opt-in app adapters for Slack/Teams/Discord accessibility structures.
- Add an optional OCR adapter only when runtime Vision capability checks confirm both `he-IL` and `en-US`; keep it behind a separate Screen Recording permission.
- Add a signed Sparkle-style updater only if automatic updates become necessary; the core app should remain network-free.
