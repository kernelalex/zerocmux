---
name: cmux-markdown
description: Open markdown files in a formatted viewer panel with live reload. Use when you need to display plans, documentation, or notes alongside the terminal with rich rendering (headings, code blocks, tables, lists).
---

# Markdown Viewer with cmux

Write a `.md` file, open it in a panel, and the panel re-renders whenever the file changes on disk. Use it for agent plans and task lists alongside the terminal, documentation and changelogs while working, and notes another process updates progressively.

```bash
# Open a markdown file as a split panel next to the current terminal
zerocmux markdown open plan.md

# Absolute path
zerocmux markdown open /path/to/PLAN.md

# Target a specific workspace
zerocmux markdown open design.md --workspace workspace:2
```

Relative paths resolve against the caller's cwd and `~` expands; the resolved absolute path comes back in the output.

## Agent usage

Write the full plan file first, then open it, so the panel never shows a partially written file. After that, overwrite or append freely: each write triggers a re-render, and atomic replacement (editor saves, `sed -i`, VS Code) is handled.

The panel automatically re-renders when the file changes on disk. This works with:

- Direct writes (`echo "..." >> plan.md`)
- Editor saves (vim, nano, VS Code)
- Atomic file replacement (write to temp, rename over original)
- Agent-generated plan files that are updated progressively

If the file is deleted, the panel shows a "file unavailable" state. During atomic replace, the panel attempts automatic reconnection within its short retry window. If the file returns later, close and reopen the panel.

## Agent Integration

### Opening a plan file

Write your plan to a file, then open it:

```bash
cat > plan.md << 'EOF'
# Task Plan

## Steps
1. Analyze the codebase
2. Implement the feature
3. Write tests
4. Verify the build
EOF

zerocmux markdown open plan.md
```

### Updating a plan in real-time

The panel live-reloads, so simply overwrite the file as work progresses:

```bash
# The markdown panel updates automatically when the file changes
echo "## Step 1: Complete" >> plan.md
```

### Recommended AGENTS.md instruction

Add this to your project's `AGENTS.md` to instruct coding agents to use the markdown viewer:

```markdown
## Plan Display

When creating a plan or task list, write it to a `.md` file and open it in cmux:

    zerocmux markdown open plan.md

The panel renders markdown with rich formatting and auto-updates when the file changes.
```

## Rendering

```bash
# Open in the caller's workspace (default -- uses CMUX_WORKSPACE_ID)
zerocmux markdown open plan.md

# Open in a specific workspace
zerocmux markdown open plan.md --workspace workspace:2

# Open splitting from a specific surface
zerocmux markdown open plan.md --surface surface:5

# Open in a specific window
zerocmux markdown open plan.md --window window:1
```

## Deep-Dive References

| Reference | When to Use |
|-----------|-------------|
| [references/commands.md](references/commands.md) | Full command syntax, options, output shape, panel behavior |
| [references/live-reload.md](references/live-reload.md) | File watching, atomic writes, unavailable-file state, performance |
