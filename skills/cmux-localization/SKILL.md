---
name: zerocmux-localization
description: "Localization rules and audit workflow for zerocmux UI strings, settings rows, menus, shortcuts, schema/config text, docs, command/help text, alerts, tooltips, and web messages. Use whenever changing user-facing text."
---

# zerocmux Localization

Use this skill for any user-facing string change.

## Hard rules

- Every user-facing string is localized. Never a bare string literal in SwiftUI `Text()`, `Button()`, alert titles, tooltips, menus, or dialogs.
- Swift/AppKit/SwiftUI: `String(localized: "key.name", defaultValue: "English text")`, with keys in `Resources/Localizable.xcstrings` translated for every supported language (currently English and Japanese).
- `defaultValue`, English fallback text, schema descriptions, and copied English strings do not count as localization.
- Localized web/docs content updates every supported message catalog (currently `web/messages/en.json` and `web/messages/ja.json`) plus any localized data structures carrying inline translations.
- A localization audit is required for every user-facing change.

## Audit checklist

Before finishing a task that changes UI, Settings rows, menus, shortcut metadata, schema/config text, docs, command/help text, alerts, or tooltips:

1. Enumerate the changed user-facing surfaces.
2. Verify each surface has entries for every supported locale.
3. Parse touched localization files.
4. Compare changed message keys across locales.
5. Use `rg` over changed Swift/TS/TSX/docs files for newly introduced bare English.
6. State the localization audit in the final handoff, or explicitly say what could not be verified.

## Related shortcut rule

Every new zerocmux-owned keyboard shortcut must be added to `KeyboardShortcutSettings`, visible/editable in Settings, supported in `~/.config/cmux/cmux.json`, and documented in the keyboard shortcut and configuration docs.

## Detailed reference

- [references/audit-workflow.md](references/audit-workflow.md): what counts as user-facing, search patterns, and handoff wording.

New keyboard shortcuts also need docs and Settings entries; see [../cmux-keyboard-shortcuts/SKILL.md](../cmux-keyboard-shortcuts/SKILL.md).
