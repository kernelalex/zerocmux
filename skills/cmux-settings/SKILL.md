---
name: zerocmux-settings
description: "View and edit zerocmux settings in ~/.config/cmux/cmux.json. Use when the user wants to change zerocmux preferences (appearance, sidebar, notifications, automation, browser, shortcuts), set a value by JSON path, validate the file, open it in an editor, or look up which keys zerocmux recognizes. Triggers on '/zerocmux-settings', 'change zerocmux setting', 'set <something> in zerocmux', 'zerocmux config', 'cmux.json', or 'rebind a zerocmux shortcut'."
---

# zerocmux-settings

zerocmux reads user settings from `~/.config/cmux/cmux.json` (JSONC). The app installs a file watcher; saving the file applies changes immediately, no restart needed. Legacy `~/.config/cmux/settings.json` is read only as a fallback for keys not present in `cmux.json`.

Schema: `https://raw.githubusercontent.com/Enigma-Labs-Technology/zerocmux/main/docs/data/cmux.schema.json`. The authoritative path list lives in `Sources/CmuxSettingsJSONPathSupport.swift` in the zerocmux checkout, and the installed skill includes a generated copy in `references/all-keys.md`. Top-level sections are `app`, `terminal`, `notifications`, `sidebar`, `sidebarAppearance`, `workspaceColors`, `automation`, `browser`, and `shortcuts`. Non-settings sections (`actions`, `ui`, `commands`, `vault`, `rightSidebar`) coexist in the same file.

## Helper script

Use the bundled helper for every read/write. It strips JSONC comments, writes atomically, and validates keys against the schema.

```bash
# From a zerocmux checkout
skills/zerocmux-settings/scripts/zerocmux-settings <subcommand>

# From an installed Codex skill
~/.codex/skills/zerocmux-settings/scripts/zerocmux-settings <subcommand>
```

For brevity in the rest of this doc, assume the script is on `$PATH` as `zerocmux-settings`. To make it so for a session from a checkout: `export PATH="$PWD/skills/zerocmux-settings/scripts:$PATH"`.

Subcommands:

| Command | What it does |
|---|---|
| `zerocmux-settings path` | Print the config path. |
| `zerocmux-settings dump` | Print the raw file (preserves comments). |
| `zerocmux-settings dump --no-comments` | Print the parsed JSON. |
| `zerocmux-settings get <a.b.c>` | Print value at dotted JSON path. |
| `zerocmux-settings set <a.b.c> <value>` | Set value. `<value>` is parsed as JSON (`true`, `42`, `"text"`, `[…]`, `{…}`); plain strings without quotes are stored as strings. |
| `zerocmux-settings unset <a.b.c>` | Delete key, reverting to the in-app default. |
| `zerocmux-settings list-supported` | List every settings JSON path the app recognizes. |
| `zerocmux-settings validate` | Parse the file and flag any unknown settings keys. |
| `zerocmux-settings open` | Open `cmux.json` in `$EDITOR`, VS Code, Cursor, or TextEdit. |

`--file <path>` overrides the target file, useful for `--file ~/.config/cmux/settings.json`.

## Workflow

1. Look up the key when the user named a setting in plain English:
   ```bash
   zerocmux-settings list-supported | rg -i 'sidebar.*terminal|terminal.*sidebar'
   ```
2. Set it. JSON literals must be valid JSON.
   ```bash
   zerocmux-settings set sidebarAppearance.matchTerminalBackground true
   zerocmux-settings set app.appearance dark
   zerocmux-settings set shortcuts.bindings.toggleSidebar cmd+b
   zerocmux-settings set shortcuts.bindings.newTab '["ctrl+b","c"]'
   zerocmux-settings set browser.hostsToOpenInEmbeddedBrowser '["localhost","*.internal.example"]'
   ```
3. Verify by reading back and validating.
   ```bash
   zerocmux-settings get sidebarAppearance.matchTerminalBackground
   zerocmux-settings validate
   ```
4. Tell the user it auto-reloaded. No app restart. If they want to revert, run `zerocmux-settings unset <key>`.

## Quick reference

- Appearance: `app.appearance` (`"system" | "light" | "dark"`), `app.appIcon`, `app.menuBarOnly`, `app.minimalMode`.
- Sidebar tint: `sidebarAppearance.matchTerminalBackground`, `.tintColor`, `.tintOpacity` (0..1).
- Sidebar details: `sidebar.hideAllDetails`, `.showBranchDirectory`, `.showPullRequests`, `.showPorts`, `.showLog`.
- Notifications: `notifications.dockBadge`, `.sound` (enum including `"none"`, `"custom_file"`), `.customSoundFilePath`, `.hooks` (array).
- Browser: `browser.defaultSearchEngine`, `.theme`, `.openTerminalLinksInCmuxBrowser`, `.hostsToOpenInEmbeddedBrowser`.
- Automation: `automation.socketControlMode` (`off | cmuxOnly | automation | password | allowAll`), `.portBase`, `.portRange`.
- Shortcuts: `shortcuts.bindings.<actionId>` = `"cmd+b"`, `["ctrl+b","c"]`, `null`, or `""` to unbind. Action ids in [references/shortcut-actions.md](references/shortcut-actions.md).

For the full list of settings, defaults, and descriptions, run `zerocmux-settings list-supported` or read [references/all-keys.md](references/all-keys.md).

## Rules

- Only edit `cmux.json`. Never edit `settings.json` unless the user explicitly asks; it is legacy and only read when the key is absent from `cmux.json`.
- Never tell the user to restart zerocmux to apply a change. The file watcher reloads on save.
- Always validate after a bulk edit: `zerocmux-settings validate`. Unknown keys mean the user pasted a key the app does not consume.
- Do not blindly overwrite top-level sections (`actions`, `ui`, `commands`, `vault`, `rightSidebar`). They live in the same file and contain non-settings config the user has hand-tuned.
- Shortcut action ids must match the schema enum. Look them up in [references/shortcut-actions.md](references/shortcut-actions.md) before binding.
- Color values must be `#RRGGBB`. Opacities are `0..1`.
- For settings the user expressed in app-level language (e.g. "Settings > Notifications > Dock badge"), translate to the matching JSON path first; the docs page at `web/app/[locale]/docs/configuration/page.tsx` mirrors the schema 1:1.
