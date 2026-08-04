# Video Recording

Status and alternatives for capturing browser automation evidence in zerocmux.

**Related**: [commands.md](commands.md), [SKILL.md](../SKILL.md)

## Contents

- [Current Status](#current-status)
- [Recommended Alternatives](#recommended-alternatives)
- [Use Cases](#use-cases)
- [Best Practices](#best-practices)

## Current Status

`zerocmux browser` currently does not expose a built-in video recording command.

Why: zerocmux browser automation runs on WKWebView, and the agent-browser style recording pipeline is Chrome/CDP-specific.

## Recommended Alternatives

### 1. Step Screenshots

```bash
zerocmux browser surface:7 screenshot > /tmp/step1.b64
zerocmux browser surface:7 click e3 --snapshot-after --json
zerocmux browser surface:7 screenshot > /tmp/step2.b64
```

### 2. Snapshot Timeline

```bash
zerocmux browser surface:7 snapshot --interactive > /tmp/snap-1.txt
zerocmux browser surface:7 click e3 --snapshot-after --json > /tmp/action-1.json
zerocmux browser surface:7 snapshot --interactive > /tmp/snap-2.txt
```

Capture before and after each mutating action, add `--snapshot-after` on state-changing clicks/fills/types, and group artifacts by timestamp or run id. Use an external screen recorder when full-motion capture is genuinely required.
