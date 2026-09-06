# ContextInput debug test checklist

## Version 0.2.3 (Build 24)

Confirm that Settings shows **Version 0.2.3 (Build 24)** beneath the ContextInput
title before testing this build.

To test source changes without replacing a signed beta installation, run
`./scripts/install-debug.sh`. This installs `/Applications/ContextInputDebug.app`
with a separate bundle identifier and no update feed. Enable **ContextInput Debug**
in Accessibility for the test. The signed `ContextInput.app` and its existing
permission remain unchanged.

### Warp known limitation

Warp is still detected generically as a terminal and the decision should be
English. Its custom remote text-input client can nevertheless continue typing in
Hebrew after macOS reports ABC. Manual Fn switching works, but synthetic
Control-Space/Fn events and a focus-refresh panel did not reproduce that hardware
action reliably, so all three experimental workarounds were removed. Testing Warp
must not show a compatibility setting or any ContextInput panel flicker.

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

- Close Settings, then launch ContextInput again from Spotlight, Finder, or the
  Applications folder. The already-running app must reopen Settings even when
  its menu-bar item is hidden by limited space.
- Press Command-W while Settings is focused. The window closes, while the אA
  menu-bar app continues running and can reopen Settings.
- Focus the Codex embedded terminal while Hebrew is active. ContextInput selects
  the configured English keyboard.
- Focus a terminal implemented with an opaque custom rendering surface, such as
  Warp. Settings must record that application, describe the focused element as a
  terminal, and decide English. The actual Warp layout is a documented limitation.
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
- In Slack, focus an empty composer after several recent Hebrew messages when an
  older English attachment, link preview, or document is still visible. The recent
  message cluster selects Hebrew; repeat with the languages reversed.
- Confirm that short controls, URLs, filenames, timestamps, and code-like text do
  not override substantive conversation messages.
- Focus a password or secure text field. ContextInput makes no change.
- Focus content containing only emoji or punctuation. ContextInput makes no
  uncertain language change.
- Confirm all language decisions are local: the app requests Accessibility but
  never Screen Recording. Only update checks/downloads contact GitHub.
- Open the menu-bar menu and Settings and confirm both contain **Check for
  Updates…**. With 0.2.0 being current, the action should report that there is no
  newer update after the beta feed is published.
- For the 0.2.2 → 0.2.3 beta update, confirm Sparkle replaces the app in place
  and System Settings still shows ContextInput enabled under Accessibility. Type
  in one English and one Hebrew control after relaunch; the macOS checkbox alone
  is not sufficient proof.
