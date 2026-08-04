---
name: zerocmux-keyboard-shortcuts
description: "Guide and apply zerocmux keyboard shortcut customization. Use when the user asks to customize, rebind, unbind, reset, audit, or create shortcut templates for zerocmux, including tmux-style, Vim-style, terminal-first, browser-heavy, iTerm/Terminal-like, or agent-triage layouts."
---

# zerocmux-keyboard-shortcuts

Use this skill to turn a user's workflow preferences into zerocmux shortcut bindings in `~/.config/cmux/cmux.json`. It should guide the user, propose compact templates, apply selected changes, and confirm the config parses with recognized keys.

## Prerequisites

- Work from a zerocmux checkout or worktree root when possible.
- Use `skills/zerocmux-settings/scripts/zerocmux-settings` for every read/write. It reads JSONC, writes atomically, and validates JSON plus recognized settings keys.
- For action IDs, read `skills/zerocmux-settings/references/shortcut-actions.md`.
- For current defaults, read `web/data/zerocmux-shortcuts.ts` or `Sources/KeyboardShortcutSettings.swift`.

```bash
if [[ -z "${CMUX_SETTINGS:-}" ]]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  for candidate in \
    "$root/skills/zerocmux-settings/scripts/zerocmux-settings" \
    "${CODEX_HOME:-$HOME/.codex}/skills/zerocmux-settings/scripts/zerocmux-settings" \
    "$HOME/.agents/skills/zerocmux-settings/scripts/zerocmux-settings"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

if [[ -z "${CMUX_SETTINGS:-}" ]]; then
  CMUX_SETTINGS="$(find_cmux_settings)" || {
    echo "zerocmux-settings helper not found; run from a zerocmux checkout or install zerocmux-settings" >&2
    exit 1
  }
fi
```

## Shortcut model

- Setting path: `shortcuts.bindings.<actionId>`.
- Single stroke: `"cmd+b"`.
- Chord: `["ctrl+b","c"]`. The first stroke needs a modifier unless the key is Space. The second stroke can be bare.
- Unbind: prefer `null` for explicit unbinds. `""`, `"none"`, `"clear"`, `"unbound"`, and `"disabled"` are accepted aliases, but `null` is the clearest JSON value and matches the templates below.
- `selectSurfaceByNumber` and `selectWorkspaceByNumber` must use a digit from 1 to 9. `cmd+1` means the full `cmd+1` through `cmd+9` family.
- `showHideAllWindows` is the only system-wide shortcut. It cannot be a chord, requires modifiers, and may be rejected by macOS if reserved.
- `globalSearch` is application-scoped and only fires while cmux is active.
- `showHideAllWindows` also requires Settings > Global Hotkey > Enable System-Wide Hotkey. The binding can validate in `cmux.json` while the feature is disabled, so warn the user to enable that setting before reporting the shortcut as usable.
- `unset` deletes a `cmux.json` override. It does not clear shortcut changes saved through the Settings UI/UserDefaults. If the user asks for true built-in defaults, tell them to use Settings > Keyboard Shortcuts > Reset Default Shortcuts after clearing file-managed overrides, then verify in the app. For `showHideAllWindows`, use Settings > Global Hotkey to restore the shortcut to `ctrl+opt+cmd+.` because Keyboard Shortcuts > Reset Default Shortcuts intentionally skips the global hotkey.
- Saving `cmux.json` live reloads. Do not tell the user to restart zerocmux.

## Workflow

1. Classify the request:
   - One-off rebind or unbind: map the phrase to an action ID, apply it, validate, and report the previous and new binding.
   - Audit-only request: inspect current bindings, validate, and summarize overrides/unbound shortcuts without writing.
   - Reset request: clarify whether the user means file-managed overrides or true built-in defaults. For file-managed resets, use `unset` for named actions. For true built-in defaults, remove file overrides and direct the user to Settings > Keyboard Shortcuts > Reset Default Shortcuts; do not report built-in defaults restored from `zerocmux-settings` alone. If `showHideAllWindows` is included, also direct them to Settings > Global Hotkey to restore `ctrl+opt+cmd+.` and the enable toggle.
   - Broad customization request: propose 3 to 5 templates from "Preset Templates" and ask the user to choose.
   - Named style such as tmux, Vim, iTerm, browser, or agent triage: select the closest template, show the changed actions and likely collisions, and ask before a bulk apply unless the user explicitly said to apply it.
2. Inspect existing config:

   ```bash
   "$CMUX_SETTINGS" path
   "$CMUX_SETTINGS" get shortcuts.bindings 2>/dev/null || printf '{}\n'
   "$CMUX_SETTINGS" validate
   ```

3. Snapshot prior values for every action you will change. A path that was absent reverts with `unset`; a path with an existing custom value reverts with `set <same-json-value>`.

   ```bash
   "$CMUX_SETTINGS" get shortcuts.bindings.focusLeft 2>/dev/null || printf '<absent>\n'
   ```

4. Apply only the chosen action paths, then `"$CMUX_SETTINGS" validate`.

   ```bash
   "$CMUX_SETTINGS" set shortcuts.bindings.newSurface '["ctrl+b","c"]'
   "$CMUX_SETTINGS" set shortcuts.bindings.focusLeft cmd+opt+h
   "$CMUX_SETTINGS" set shortcuts.bindings.sendFeedback null
   ```

5. Read back each changed action: `"$CMUX_SETTINGS" get shortcuts.bindings.newSurface`.
6. Finish with the template name, changed actions, and exact revert commands from the snapshot.

## Preset templates

Apply action by action, never by overwriting the whole `shortcuts.bindings` object.

### Tmux Prefix

For users who want one terminal-style shortcut namespace and accept that `ctrl+b` starts a zerocmux chord instead of going directly to the shell.

```bash
"$CMUX_SETTINGS" set shortcuts.bindings.newSurface '["ctrl+b","c"]'
"$CMUX_SETTINGS" set shortcuts.bindings.closeTab '["ctrl+b","x"]'
"$CMUX_SETTINGS" set shortcuts.bindings.nextSurface '["ctrl+b","n"]'
"$CMUX_SETTINGS" set shortcuts.bindings.prevSurface '["ctrl+b","p"]'
"$CMUX_SETTINGS" set shortcuts.bindings.selectSurfaceByNumber '["ctrl+b","1"]'
"$CMUX_SETTINGS" set shortcuts.bindings.splitRight '["ctrl+b","v"]'
"$CMUX_SETTINGS" set shortcuts.bindings.splitDown '["ctrl+b","s"]'
"$CMUX_SETTINGS" set shortcuts.bindings.focusLeft '["ctrl+b","h"]'
"$CMUX_SETTINGS" set shortcuts.bindings.focusDown '["ctrl+b","j"]'
"$CMUX_SETTINGS" set shortcuts.bindings.focusUp '["ctrl+b","k"]'
"$CMUX_SETTINGS" set shortcuts.bindings.focusRight '["ctrl+b","l"]'
"$CMUX_SETTINGS" set shortcuts.bindings.toggleSplitZoom '["ctrl+b","z"]'
"$CMUX_SETTINGS" set shortcuts.bindings.toggleTerminalCopyMode '["ctrl+b","["]'
"$CMUX_SETTINGS" set shortcuts.bindings.equalizeSplits '["ctrl+b","="]'
```

### macOS Terminal/iTerm Restore

For users who want surface, split, and tab behavior to feel like common macOS terminals again. These actions already match zerocmux built-in defaults when no Settings UI override exists, so unset file overrides instead of writing default values.

```bash
for a in newSurface closeTab nextSurface prevSurface selectSurfaceByNumber \
         splitRight splitDown toggleSplitZoom toggleTerminalCopyMode renameTab; do
  "$CMUX_SETTINGS" unset "shortcuts.bindings.$a"
done
```

### Vim Pane Navigation

Prefix-free pane movement with no arrow keys.

```bash
"$CMUX_SETTINGS" set shortcuts.bindings.focusLeft cmd+opt+h
"$CMUX_SETTINGS" set shortcuts.bindings.focusDown cmd+opt+j
"$CMUX_SETTINGS" set shortcuts.bindings.focusUp cmd+opt+k
"$CMUX_SETTINGS" set shortcuts.bindings.focusRight cmd+opt+l
"$CMUX_SETTINGS" set shortcuts.bindings.splitRight cmd+opt+v
"$CMUX_SETTINGS" set shortcuts.bindings.splitDown cmd+opt+s
"$CMUX_SETTINGS" set shortcuts.bindings.toggleSplitZoom cmd+opt+z
"$CMUX_SETTINGS" set shortcuts.bindings.equalizeSplits cmd+opt+=
```

### Agent Triage

Unread handling on one key family. `toggleUnread` stays on `cmd+opt+u` so this composes with Vim Pane Navigation without colliding with `cmd+opt+j`.

```bash
"$CMUX_SETTINGS" set shortcuts.bindings.showNotifications cmd+u
"$CMUX_SETTINGS" set shortcuts.bindings.jumpToUnread cmd+j
"$CMUX_SETTINGS" set shortcuts.bindings.markOldestUnreadAndJumpNext cmd+shift+j
"$CMUX_SETTINGS" set shortcuts.bindings.toggleUnread cmd+opt+u
"$CMUX_SETTINGS" set shortcuts.bindings.triggerFlash cmd+shift+h
"$CMUX_SETTINGS" set shortcuts.bindings.focusRightSidebar cmd+shift+e
```

### Workspace And Surface Lanes

Workspaces and surfaces on distinct number and bracket lanes.

```bash
"$CMUX_SETTINGS" set shortcuts.bindings.selectWorkspaceByNumber cmd+1
"$CMUX_SETTINGS" set shortcuts.bindings.selectSurfaceByNumber cmd+opt+1
"$CMUX_SETTINGS" set shortcuts.bindings.nextSidebarTab 'cmd+opt+]'
"$CMUX_SETTINGS" set shortcuts.bindings.prevSidebarTab 'cmd+opt+['
"$CMUX_SETTINGS" set shortcuts.bindings.nextSurface 'cmd+shift+]'
"$CMUX_SETTINGS" set shortcuts.bindings.prevSurface 'cmd+shift+['
```

### Browser Defaults Restore

For users who changed too much and want embedded-browser behavior to match common macOS browser shortcuts again. Use `unset` to clear file overrides so future zerocmux defaults still apply when no Settings UI override exists.

```bash
for a in openBrowser focusBrowserAddressBar browserBack browserForward browserReload \
         browserZoomIn browserZoomOut browserZoomReset toggleBrowserDeveloperTools \
         showBrowserJavaScriptConsole find findNext findPrevious; do
  "$CMUX_SETTINGS" unset "shortcuts.bindings.$a"
done
```

### Terminal-First Cleanup

Fewer app-level shortcuts. Prefer unbinding only the actions the user names; this is a starting proposal.

```bash
for a in renameTab renameWorkspace editWorkspaceDescription triggerFlash sendFeedback; do
  "$CMUX_SETTINGS" set "shortcuts.bindings.$a" null
done
```

## Rules

- Do not edit `~/.config/cmux/settings.json` unless the user explicitly asks; it is legacy fallback config.
- Do not overwrite all of `shortcuts.bindings` unless the user wants a full replacement.
- Do not invent action IDs. Validate against the schema or `shortcut-actions.md`.
- Do not apply a broad template without showing the changed actions first unless the user explicitly said to apply that named template.
- Do not promise conflict detection from `zerocmux-settings validate`; it validates JSON and supported keys, not shortcut syntax, macOS reservation, or every focus-context conflict.
- Before assigning `cmd+[` or `cmd+]` to application-scoped actions, warn that they collide with common browser Back/Forward behavior unless the browser actions are also changed or unbound.
- Prefer `unset` to clear file-managed overrides for individual actions. Do not call this a built-in default reset unless Settings UI/UserDefaults values have also been reset:

  ```bash
  "$CMUX_SETTINGS" unset shortcuts.bindings.focusLeft
  "$CMUX_SETTINGS" validate
  ```
