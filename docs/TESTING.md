# ContextInput debug test checklist

## Version 0.1.9 (Build 10)

Confirm that Settings shows **Version 0.1.9 (Build 10)** beneath the ContextInput
title before testing this build.

### Warp acceptance test (still requires real typing)

1. Select Hebrew in another app, then click Warp's command prompt.
2. Wait one second, press the physical A/B/C keys, and do not press Return.
3. Pass: Latin characters appear. Delete the test characters manually.
4. Open ContextInput Settings and inspect the selectable **Last switch** text
   (scroll down if necessary). It preserves the source observed before the request,
   at +250 ms, and at +650 ms while Warp was focused. The opaque-terminal path
   reapplies the target once at +250 ms even if macOS already reports it selected.
5. If Hebrew still appears, copy Last switch and the focus/decision/evidence rows.
   macOS reporting the target selected is not proof that Warp used it to type.

The earlier Settings source row was refreshed after opening Settings and could
not establish which layout Warp used. It is now labeled **Current input source
(live)**; use Last switch for historical observations. `Command Input.` on an
AXWindow must no longer be classified as an existing draft.

Repeat using both a click and Command-Tab to return to Warp. Also test immediately
typing or manually switching layouts after focusing: the delayed retry must be
canceled upon observed keyboard/modifier activity. Leaving the app, disabling
switching, or changing the selected target must cancel stale retries. If the
activity monitor cannot be installed, delayed switching is disabled for safety.

### Regression checklist

- Press Command-W while Settings is focused. The window closes, while the אA
  menu-bar app continues running and can reopen Settings.
- Focus the Codex embedded terminal while Hebrew is active. ContextInput selects
  the configured English keyboard.
- Focus a terminal implemented with an opaque custom rendering surface, such as
  Warp, while Hebrew is active. Settings must record that application, describe
  the focused element as a terminal, and select the configured English keyboard.
- As negative controls, confirm Cursor's standard embedded terminal still selects
  English, and a normal search or text field inside a terminal-capable app is
  classified from its own draft/context rather than forced to English.
- Focus Safari's address bar when it contains an English URL on a Hebrew page.
  The field's existing English value takes priority and selects English.
- Focus a field with an existing Hebrew or English draft. The draft takes
  priority over surrounding page or conversation text.
- Focus an empty composer in a Hebrew ChatGPT/Codex session. The recent Hebrew
  conversation selects Hebrew even when nearby controls and filenames are in
  English. Its English placeholder (for example, "Do anything") is ignored and
  must not appear as either `the existing draft` or the decision evidence.
- Switch directly between an English session and a Hebrew session when ChatGPT
  reuses the same composer. Click the composer after selecting each session; the
  language must be reevaluated even though the Accessibility element is unchanged.
- In Settings, verify that Reason describes the selected signal and that Context
  items is greater than zero for a readable ChatGPT conversation.
- Confirm that Nearest context contains text from the open conversation pane, not
  a stale ChatGPT window title, another ChatGPT task, WhatsApp's chat list, or a
  document side panel.
- In WhatsApp, confirm short Hebrew messages are shown without English delivery
  wrappers such as `Received from`, `Sent to`, dates, or delivery status. English
  synchronization and encryption notices must not influence the decision.
- Focus an empty composer in an English ChatGPT/Codex session. The recent English
  conversation selects English.
- Confirm that short controls, URLs, filenames, timestamps, and code-like text do
  not override substantive conversation messages.
- Focus a password or secure text field. ContextInput makes no change.
- Focus content containing only emoji or punctuation. ContextInput makes no
  uncertain language change.
- Confirm all decisions are local: the app requests Accessibility permission but
  never Screen Recording or network access.
