# Session Management

zerocmux uses isolated browser contexts per surface. Treat each browser surface as its own session.

## Parallel sessions

Each `cmux browser open` returns a new surface ref; drive them independently.

```bash
# session A
zerocmux browser open https://app.example.com/login --json
# -> surface:7

# session B
zerocmux browser open https://example.com --json
# -> surface:8

zerocmux browser surface:7 get url
zerocmux browser surface:8 get url
```

## Isolation Properties

Each surface has independent:
- cookies
- localStorage/sessionStorage
- tab list and active tab
- navigation history

## State Persistence

### Save State

```bash
zerocmux browser surface:7 state save /tmp/auth-state.json
```

### Load State

```bash
zerocmux browser surface:8 state load /tmp/auth-state.json
zerocmux browser surface:8 goto https://app.example.com/dashboard
```

## Common Patterns

### Reuse Auth Across New Surface

```bash
zerocmux browser open https://app.example.com/login --json
# login on surface:7 ...
zerocmux browser surface:7 state save /tmp/auth.json

zerocmux browser open https://app.example.com --json
# assume surface:8
zerocmux browser surface:8 state load /tmp/auth.json
zerocmux browser surface:8 goto https://app.example.com/dashboard
```

### Parallel Multi-Site Tasks

```bash
zerocmux browser open https://site-a.example --json
zerocmux browser open https://site-b.example --json
zerocmux browser open https://site-c.example --json

zerocmux browser surface:11 get text body > /tmp/a.txt
zerocmux browser surface:12 get text body > /tmp/b.txt
zerocmux browser surface:13 get text body > /tmp/c.txt
```

## Cleanup

```bash
zerocmux close-surface --surface surface:7
zerocmux close-surface --surface surface:8
rm -f /tmp/auth-state.json
```

## Best practices

Log surface refs in script output so actions stay attributable, keep one task per surface to avoid ref churn, save state after successful auth milestones, and re-snapshot after switching tabs or pages inside a surface.
