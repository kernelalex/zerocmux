# Handles and Identify

Most v2-backed commands accept a UUID, a short ref (`window:N`, `workspace:N`, `pane:N`, `surface:N`), or an index where legacy index-based commands still allow it.

```bash
zerocmux identify --json
```

Returns current focused topology plus optional caller resolution.

## Caller Override

```bash
zerocmux identify --workspace workspace:2
zerocmux identify --workspace workspace:2 --surface surface:8
```

Useful for agents that need to route relative actions from a known caller anchor.

## Output Shaping

```bash
zerocmux --json identify                 # refs-first output
zerocmux --json --id-format both identify
zerocmux --json --id-format uuids identify
```
