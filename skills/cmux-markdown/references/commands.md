# Command Reference (cmux Markdown)

```bash
zerocmux markdown open <path>
zerocmux markdown <path>          # shorthand (implicit "open")
```

| Flag | Description | Default |
|------|-------------|---------|
| `--workspace <id\|ref\|index>` | Target workspace | `$CMUX_WORKSPACE_ID` |
| `--surface <id\|ref\|index>` | Source surface to split from | Focused surface |
| `--window <id\|ref>` | Target window | Current window |

## Output

```
OK surface=surface:8 pane=pane:3 path=/absolute/path/to/file.md
```

`--json` returns `window_id`, `workspace_id`, `pane_id`, `surface_id`, and `path`.

## Panel behavior

The panel opens as a horizontal split to the right of the source surface. The tab shows the filename and a document icon; the file path appears as a breadcrumb at the top. Content is read-only with text selection enabled.

Markdown panels are saved and restored across sessions and re-read the file from disk on restore. A panel is not recreated if the file no longer exists at restore time.

```bash
# These are equivalent when run from /Users/me/project
zerocmux markdown open plan.md
zerocmux markdown open ./plan.md
zerocmux markdown open /Users/me/project/plan.md
```

## Panel Behavior

- The panel opens as a **horizontal split** to the right of the source surface.
- The tab title shows the filename (e.g., `plan.md`).
- The tab icon is a document icon.
- Content is **read-only** with text selection enabled.
- The file path is displayed as a breadcrumb at the top of the panel.

## Session Persistence

Markdown panels are saved and restored across sessions. On restore, the panel re-reads the file from disk. If the file no longer exists at restore time, the panel is not recreated.

## Help

```bash
zerocmux markdown --help
zerocmux markdown -h
```

See also:
- [live-reload.md](live-reload.md)
