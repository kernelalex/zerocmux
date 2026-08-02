---
name: zerocmux
description: End-user control of zerocmux topology and routing (windows, workspaces, panes/surfaces, focus, moves, reorder, identify, trigger flash). Use when automation needs deterministic placement and navigation in a multi-pane zerocmux layout.
---

# zerocmux Core Control

Use this skill to control non-browser zerocmux topology and routing.

- **Window**: top-level macOS cmux window.
- **Workspace**: tab-like group within a window.
- **Pane**: split container in a workspace.
- **Surface**: a tab within a pane (terminal or browser panel).

- Window: top-level macOS zerocmux window.
- Workspace: tab-like group within a window.
- Pane: split container in a workspace.
- Surface: a tab within a pane (terminal or browser panel).

## Fast Start

```bash
# identify current caller context
zerocmux identify --json

# list topology
zerocmux list-windows
zerocmux list-workspaces
zerocmux list-panes
zerocmux list-pane-surfaces --pane pane:1

# create/focus/move
zerocmux new-workspace
zerocmux new-split right --panel pane:1
zerocmux move-surface --surface surface:7 --pane pane:2 --focus true
zerocmux split-off --surface surface:7 right
zerocmux reorder-surface --surface surface:7 --before surface:3

# workspace context-menu actions (color, description, rename, pin, ...)
cmux workspace-action --action set-color --color Blue
cmux workspace-action --action set-description --description "Ship checklist"

# attention cue
zerocmux trigger-flash --surface surface:7
```

## Handle model

Use `zerocmux docs settings` before changing zerocmux-owned settings. It prints the docs URL, schema URL, raw GitHub resources, cmux.json paths, and reload command.

```bash
zerocmux docs settings
zerocmux settings path
```

zerocmux-owned settings live in `~/.config/cmux/cmux.json`. Legacy `~/.config/cmux/settings.json` and `~/Library/Application Support/com.cmuxterm.app/settings.json` files are read only as fallback for missing keys. Before editing, copy any existing `cmux.json` file to a timestamped `.bak` next to it so the user can revert. Edit the user file, then reload:

```bash
zerocmux reload-config
```

Use zerocmux settings for app behavior, sidebar, notifications, browser behavior, automation, workspace colors, and zerocmux-owned shortcuts. Terminal rendering settings such as font, cursor style, theme, and scrollback belong in Ghostty config.

Open the UI when useful:

```bash
zerocmux settings
zerocmux settings cmux-json
zerocmux settings shortcuts
```

## Handle Model

- Default output uses short refs: `window:N`, `workspace:N`, `pane:N`, `surface:N`.
- UUIDs are still accepted as inputs.
- Request UUID output only when needed: `--id-format uuids|both`.

## Deep-Dive References

| Reference | When to Use |
|-----------|-------------|
| [references/handles-and-identify.md](references/handles-and-identify.md) | Handle syntax, self-identify, caller targeting |
| [references/windows-workspaces.md](references/windows-workspaces.md) | Window/workspace lifecycle, reorder/move, and context-menu actions (color, description, rename) |
| [references/panes-surfaces.md](references/panes-surfaces.md) | Splits, surfaces, move/reorder, focus routing |
| [references/trigger-flash-and-health.md](references/trigger-flash-and-health.md) | Flash cue and surface health checks |
| [../cmux-workspace/SKILL.md](../cmux-workspace/SKILL.md) | Current caller workspace rules and non-disruptive automation |
| [../cmux-settings/SKILL.md](../cmux-settings/SKILL.md) | Safe cmux.json settings edits and validation |
| [../cmux-browser/SKILL.md](../cmux-browser/SKILL.md) | Browser automation on surface-backed webviews |
| [../cmux-markdown/SKILL.md](../cmux-markdown/SKILL.md) | Markdown viewer panel with live file watching |
