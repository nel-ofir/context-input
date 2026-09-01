# ContextInput debug test checklist

## Version 0.1.7 (Build 8)

Confirm that Settings shows **Version 0.1.7 (Build 8)** beneath the ContextInput
title before testing this build.

- Press Command-W while Settings is focused. The window closes, while the אA
  menu-bar app continues running and can reopen Settings.
- Focus the Codex embedded terminal while Hebrew is active. ContextInput selects
  the configured English keyboard.
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
