# Windows and Workspaces

```bash
zerocmux list-windows
zerocmux current-window
zerocmux list-workspaces
zerocmux current-workspace
```

## Create/Focus/Close

```bash
zerocmux new-window
zerocmux focus-window --window window:2
zerocmux close-window --window window:2

zerocmux new-workspace
zerocmux select-workspace --workspace workspace:4
zerocmux close-workspace --workspace workspace:4
```

## Reorder and Move

```bash
zerocmux reorder-workspace --workspace workspace:4 --before workspace:2
zerocmux move-workspace-to-window --workspace workspace:4 --window window:1
```

## Context-Menu Actions

`cmux workspace-action` runs the workspace right-click actions (color, description, rename, pin, read state, ordering). Defaults to the caller's workspace; override with `--workspace <id|ref|index>`.

```bash
cmux workspace-action --action set-color --color Blue      # name or #RRGGBB hex
cmux workspace-action --action set-description --description "Ship checklist"
cmux workspace-action --action rename --title "infra"
cmux workspace-action --action pin
cmux workspace-action --action clear-color
```

Other actions: `unpin`, `clear-name`, `clear-description`, `mark-read`/`mark-unread`, `move-up`/`move-down`/`move-top`, `close-others`/`close-above`/`close-below`. Named colors: Red, Crimson, Orange, Amber, Olive, Green, Teal, Aqua, Blue, Navy, Indigo, Purple, Magenta, Rose, Brown, Charcoal. `set-color` tints a single workspace (stored as workspace state); the `workspaceColors` block in `cmux.json` defines the shared palette and selection/badge colors, not per-workspace assignments.
