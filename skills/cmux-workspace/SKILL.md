---
name: zerocmux-workspace
description: "Work inside the current zerocmux workspace and terminal. Use for zerocmux workspace, current workspace, caller surface, panes, surfaces, socket targeting, and non-interfering zerocmux automation."
---

# zerocmux Workspace

Use this skill when a task should be scoped to the zerocmux workspace that invoked the agent. A workspace is the sidebar tab-like unit in zerocmux. It contains split panes, and each pane contains one or more surfaces. A surface is the terminal or browser session the user interacts with.

- **Window**: a macOS cmux window.
- **Workspace**: a sidebar entry. The UI calls it a tab; CLI/socket APIs call it a workspace.
- **Pane**: a split region inside a workspace.
- **Surface**: a tab inside a pane, terminal or browser.
- **Panel**: internal content type inside a surface. Prefer CLI surface commands over panel internals.

## Default rule

Do not assume the visually focused zerocmux workspace is the right target. An agent can be running in one workspace while the user is looking at another. Prefer the caller environment first:

```bash
printf 'workspace=%s\nsurface=%s\nsocket=%s\n' \
  "${CMUX_WORKSPACE_ID:-}" \
  "${CMUX_SURFACE_ID:-}" \
  "${CMUX_SOCKET_PATH:-}"
zerocmux identify --json
```

Use `CMUX_WORKSPACE_ID` as the default workspace anchor and `CMUX_SURFACE_ID` as the default caller terminal/surface anchor. If those are missing, use `zerocmux identify --json` and be explicit that you are using the currently focused zerocmux context.

## Non-disruptive automation

Treat layout and focus as separate concerns. `select-workspace`, `focus-pane`, `focus-panel`, and focus-changing `tab-action` verbs are user-affecting actions, like clicks. Never call them speculatively, even inside the caller's own workspace, since the user may be looking elsewhere.

Build layout additively in one shot, using commands that create a pane already populated with the right surface:

```bash
# pane and content in one call, no follow-up needed
zerocmux new-pane --workspace "${CMUX_WORKSPACE_ID}" --type browser --direction right --url "http://127.0.0.1:8765"
zerocmux new-pane --workspace "${CMUX_WORKSPACE_ID}" --type terminal --direction down
```

Avoid create-then-move-then-focus chains. Pass `--focus false` wherever the verb supports it (`move-surface --focus false` preserves the user's attention; more commands may grow the flag, see https://github.com/manaflow-ai/cmux/issues/1418 and https://github.com/manaflow-ai/cmux/issues/2820). If a layout command rejects a valid `surface:` or `pane:` ref, report the bug and stop rather than working around it by focusing.

Pass `--focus false` whenever the verb supports it. `move-surface --focus false` preserves the user's current attention. Other commands may grow the same flag over time (https://github.com/kernelalex/zerocmux/issues/1418, https://github.com/kernelalex/zerocmux/issues/2820).

For auxiliary output (preview apps, TUIs, logs, one-off shells, browser checks), reuse one helper pane to the right of the caller terminal. Inspect first with `cmux identify --json`, `cmux list-panes`, and `cmux list-pane-surfaces`, then:

When opening auxiliary output for the current task (preview apps, TUIs, logs, one-off shells, browser checks), keep the workspace organized by reusing a helper pane to the right of the caller terminal.

First inspect the caller context and panes:

```bash
zerocmux identify --json
zerocmux list-panes --workspace "${CMUX_WORKSPACE_ID:-}" --json
zerocmux list-pane-surfaces --workspace "${CMUX_WORKSPACE_ID:-}" --json
```

Use this policy:

- If the caller workspace already has a non-caller helper pane, add a new surface to that pane instead of creating another pane:
  ```bash
  zerocmux new-surface --workspace "${CMUX_WORKSPACE_ID:-}" --pane pane:<helper> --type terminal --focus false
  ```
- No helper pane: create exactly one.
  ```bash
  zerocmux new-pane --workspace "${CMUX_WORKSPACE_ID:-}" --type terminal --direction right --focus false
  ```
- Multiple obvious stale helper panes from this same automation, and the user asked to tidy: keep one and clean up duplicates. Never close a pane you cannot confidently identify as stale helper output.

Send commands to the new or reused surface by explicit surface ref. Repeated "open it" requests create tabs inside the existing right helper pane, not more splits.

## Caller terminal

- Window: a macOS zerocmux window.
- Workspace: a sidebar entry. The UI may call it a tab, but CLI/socket APIs call it a workspace.
- Pane: a split region inside a workspace.
- Surface: a tab inside a pane. Surfaces can be terminals or browser panels.
- Panel: internal content type inside a surface. Prefer CLI surface commands instead of panel internals.

## Inspect Current Context

```bash
zerocmux identify --json
zerocmux current-workspace --json
zerocmux list-workspaces --json
zerocmux list-panes --workspace "${CMUX_WORKSPACE_ID:-}" --json
zerocmux list-pane-surfaces --workspace "${CMUX_WORKSPACE_ID:-}" --json
zerocmux list-panels --workspace "${CMUX_WORKSPACE_ID:-}" --json
```

Use `--id-format both` when logs or handoffs need stable UUIDs plus human refs:

```bash
zerocmux --json --id-format both identify
```

## Workspace-Scoped Actions

Prefer explicit workspace flags even when env vars are set. It makes automation auditable and avoids affecting a focused workspace in another window.

```bash
# create a new workspace when the user asks for a new task area
zerocmux new-workspace --name "debug auth" --cwd "$PWD"

# rename / close (only when explicitly requested)
zerocmux rename-workspace --workspace "${CMUX_WORKSPACE_ID:-}" -- "build fix"
zerocmux close-workspace --workspace workspace:4
zerocmux close-surface --workspace "${CMUX_WORKSPACE_ID:-}" --surface surface:3

# additive layout (safe, no focus side effects beyond the command's own defaults)
zerocmux new-pane --workspace "${CMUX_WORKSPACE_ID:-}" --type terminal --direction right
zerocmux new-surface --workspace "${CMUX_WORKSPACE_ID:-}" --type terminal

# focus-changing (USER-AFFECTING, only on explicit ask, see Non-Disruptive Automation above)
zerocmux select-workspace --workspace workspace:2
zerocmux focus-pane --workspace "${CMUX_WORKSPACE_ID:-}" --pane pane:2
zerocmux focus-panel --workspace "${CMUX_WORKSPACE_ID:-}" --panel surface:3
```

## Caller Terminal

The current terminal is the surface that invoked the agent. Treat it as the safest anchor for relative operations.

```bash
# send to the focused terminal in the caller workspace
zerocmux send "npm test\n"

# send to the exact caller surface
zerocmux send --surface "${CMUX_SURFACE_ID:-}" "git status\n"
zerocmux send-key --surface "${CMUX_SURFACE_ID:-}" enter
```

Do not send keystrokes, close surfaces, or change focus in another workspace unless the user named that target.

## Moving Surfaces

Reorder a surface within its pane:

```bash
zerocmux move-surface --surface "${CMUX_SURFACE_ID}" --before surface:3
zerocmux move-surface --surface "${CMUX_SURFACE_ID}" --after surface:3
zerocmux move-surface --surface "${CMUX_SURFACE_ID}" --index 0
```

Move a surface to another existing pane. Pass `--focus false` to keep the user's current attention put:

```bash
zerocmux move-surface --surface surface:240 --pane pane:172 --focus false
```

Split a surface off into a new pane:

```bash
zerocmux drag-surface-to-split --surface surface:240 down
```

Known papercut: `drag-surface-to-split` currently routes through V1 and resolves the workspace via UI focus, so it can fail with `ERROR: Surface not found` when the caller's workspace is not the visually focused one. Tracked at https://github.com/kernelalex/zerocmux/issues/1901, related to https://github.com/kernelalex/zerocmux/issues/3189. Until that lands, prefer building the layout additively (see Non-Disruptive Automation above) over create-then-split.

## Sidebar state

Attach status, progress, and logs to the current workspace so the sidebar reflects this task.

```bash
zerocmux set-status build "running" --workspace "${CMUX_WORKSPACE_ID:-}" --color "#ff9500"
zerocmux set-progress 0.4 --label "Building" --workspace "${CMUX_WORKSPACE_ID:-}"
zerocmux log --workspace "${CMUX_WORKSPACE_ID:-}" --level info -- "Started build"
zerocmux sidebar-state --workspace "${CMUX_WORKSPACE_ID:-}" --json
zerocmux clear-status build --workspace "${CMUX_WORKSPACE_ID:-}"
zerocmux clear-progress --workspace "${CMUX_WORKSPACE_ID:-}"
```

## Contributor reloads

For zerocmux app/runtime changes in a zerocmux source checkout, use tagged reloads from the active worktree. A tagged reload creates an isolated app name, bundle ID, debug socket, and DerivedData path.

```bash
./scripts/reload.sh --tag <short-tag>
```

Never build or launch untagged `zerocmux DEV`. If tests or tools need a socket, use the tag-specific socket:

```bash
CMUX_SOCKET_PATH=/tmp/zerocmux-debug-<short-tag>.sock zerocmux identify --json
```

## Socket access

Use the socket path provided by zerocmux before falling back to defaults:

```bash
SOCK="${CMUX_SOCKET_PATH:-/tmp/zerocmux.sock}"
```

Socket access can be off, restricted to zerocmux-spawned processes, or allow all local processes. If a command cannot connect, inspect capabilities before changing settings:

```bash
zerocmux capabilities --json
zerocmux ping
```

## References

- [references/commands.md](references/commands.md) enumerates workspace, pane, surface, notification, and utility commands.
- [../zerocmux-browser/SKILL.md](../zerocmux-browser/SKILL.md) covers browser surfaces with the same current-workspace rule.

## Rules

- Work in the caller workspace by default; prefer explicit `--workspace` and `--surface` flags for mutating actions even when env vars are set, so automation is auditable.
- Never call `focus-pane`, `focus-panel`, `select-workspace`, or focus-changing `tab-action` verbs unless the user explicitly asked.
- Pass `--focus false` on `move-surface` and any creation verb that supports it.
- Build layout additively with `new-pane --type ... --url ...`, not create-then-move-then-focus.
- If a CLI command rejects a valid surface or pane ref, report it. Do not work around by focusing.
- Do not close, focus, move, or send input to another workspace unless the user names that target.
- Use short refs for chat and command examples. Use UUIDs only for logs, persistence, or debugging.
- For app/runtime changes in a zerocmux source checkout, reload with `./scripts/reload.sh --tag <tag>` from the worktree before dogfood handoff.
