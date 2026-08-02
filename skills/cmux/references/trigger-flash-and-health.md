# Trigger Flash and Surface Health

Flash a surface or workspace for visual confirmation in the UI:

```bash
zerocmux trigger-flash --surface surface:7
zerocmux trigger-flash --workspace workspace:2
```

Detect hidden, detached, or non-windowed surfaces before routing focused input when UI state may be stale:

```bash
zerocmux surface-health
zerocmux surface-health --workspace workspace:2
```
