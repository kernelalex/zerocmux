---
name: cmux-browser
description: End-user browser automation with zerocmux. Use when you need to open sites, interact with pages, wait for state changes, and extract data from zerocmux browser surfaces.
---

# Browser Automation with zerocmux

Use this skill for browser tasks inside zerocmux webviews.

Open or target a browser surface, verify navigation with `get url`, snapshot for fresh element refs, act on refs, wait for the state change, re-snapshot.

```bash
zerocmux --json browser open https://example.com
# use returned surface ref, for example: surface:7

zerocmux browser surface:7 get url
zerocmux browser surface:7 wait --load-state complete --timeout-ms 15000
zerocmux browser surface:7 snapshot --interactive
zerocmux browser surface:7 fill e1 "hello"
zerocmux --json browser surface:7 click e2 --snapshot-after
zerocmux browser surface:7 snapshot --interactive
```

If `get url` is empty or `about:blank`, navigate first instead of waiting on load state. Re-snapshot after navigation, modal open/close, or major DOM changes; refs go stale.

## Surface targeting

`browser open` targets the workspace of the terminal running the command (`CMUX_WORKSPACE_ID`), even when another workspace is focused. Override with `--workspace` / `--window`:

```bash
# identify current context
zerocmux identify --json

# open routed to a specific topology target
zerocmux browser open https://example.com --workspace workspace:2 --window window:1 --json
```

Output defaults to short refs (`surface:N`, `pane:N`, `workspace:N`, `window:N`); UUIDs are accepted on input, and `--id-format uuids|both` requests them on output. Keep one `surface:N` per task.

## Wait Support

zerocmux supports wait patterns similar to agent-browser:

```bash
zerocmux browser <surface> wait --selector "#ready" --timeout-ms 10000
zerocmux browser <surface> wait --text "Success" --timeout-ms 10000
zerocmux browser <surface> wait --url-contains "/dashboard" --timeout-ms 10000
zerocmux browser <surface> wait --load-state complete --timeout-ms 15000
zerocmux browser <surface> wait --function "document.readyState === 'complete'" --timeout-ms 10000
```

## Viewport sizing (WKWebView)

`cmux browser <surface> viewport <width> <height>` sets an exact logical viewport from 1 to 4096 CSS pixels. The page is aspect-fitted inside its existing pane, so pane layout and focus stay unchanged, and screenshots use the requested logical dimensions. `viewport reset` returns to native pane sizing.

```bash
zerocmux --json browser open https://example.com/signup
zerocmux browser surface:7 get url
zerocmux browser surface:7 wait --load-state complete --timeout-ms 15000
zerocmux browser surface:7 snapshot --interactive
zerocmux browser surface:7 fill e1 "Jane Doe"
zerocmux browser surface:7 fill e2 "jane@example.com"
zerocmux --json browser surface:7 click e3 --snapshot-after
zerocmux browser surface:7 wait --url-contains "/welcome" --timeout-ms 15000
zerocmux browser surface:7 snapshot --interactive
```

### Clear an Input

```bash
zerocmux browser surface:7 fill e11 "" --snapshot-after --json
zerocmux browser surface:7 get value e11 --json
```

### Stable Agent Loop (Recommended)

```bash
# navigate -> verify -> wait -> snapshot -> action -> snapshot
zerocmux browser surface:7 get url
zerocmux browser surface:7 wait --load-state complete --timeout-ms 15000
zerocmux browser surface:7 snapshot --interactive
zerocmux --json browser surface:7 click e5 --snapshot-after
zerocmux browser surface:7 snapshot --interactive
```

If `get url` is empty or `about:blank`, navigate first instead of waiting on load state.

## Deep-Dive References

| Reference | When to Use |
|-----------|-------------|
| [references/commands.md](references/commands.md) | Full browser command mapping and quick syntax |
| [references/snapshot-refs.md](references/snapshot-refs.md) | Ref lifecycle and stale-ref troubleshooting |
| [references/authentication.md](references/authentication.md) | Login/OAuth/2FA patterns and state save/load |
| [references/authentication.md#saving-authentication-state](references/authentication.md#saving-authentication-state) | Save authenticated state right after login |
| [references/session-management.md](references/session-management.md) | Multi-surface isolation and state persistence patterns |
| [references/video-recording.md](references/video-recording.md) | Current recording status and practical alternatives |
| [references/proxy-support.md](references/proxy-support.md) | Proxy behavior in WKWebView and workarounds |

## Ready-to-Use Templates

| Template | Description |
|----------|-------------|
| [templates/form-automation.sh](templates/form-automation.sh) | Snapshot/ref form fill loop |
| [templates/authenticated-session.sh](templates/authenticated-session.sh) | Login once, save/load state |
| [templates/capture-workflow.sh](templates/capture-workflow.sh) | Navigate + capture snapshots/screenshots |

## Viewport Sizing (WKWebView)

Use `cmux browser <surface> viewport <width> <height>` to set an exact logical
viewport from 1...4096 CSS pixels. The page is aspect-fitted inside its existing
pane, so pane layout and focus stay unchanged; screenshots use the requested
logical dimensions. Run `cmux browser <surface> viewport reset` to follow native
pane sizing again. Close or detach the browser inspector first because its
inspector-managed split layout cannot be combined with viewport emulation.
Large viewport and page-zoom combinations are bounded; the viewport command
returns structured `maximum_page_zoom` details without changing the current
viewport when the combination exceeds the WKWebView render limits.
Opening or redocking an attached browser inspector resets emulation to native
sizing because WebKit owns the attached split geometry.

## Limits (WKWebView)

Offline emulation, trace/screencast recording, network route interception/mocking, and low-level raw input injection return `not_supported`; they depend on Chrome/CDP-only APIs. Use `click`, `fill`, `press`, `scroll`, `wait`, `snapshot` instead.

## Troubleshooting `js_error`

Some complex pages reject the JavaScript behind `snapshot --interactive` and `eval`. Recover by checking whether the page actually navigated, then falling back to raw text or HTML:

```bash
zerocmux browser surface:7 get url
zerocmux browser surface:7 get text body
zerocmux browser surface:7 get html body
```

If it still fails, navigate to a simpler intermediate page and retry from there.

## Deep-dive references

| Reference | When to Use |
|-----------|-------------|
| [references/commands.md](references/commands.md) | Full command mapping, `agent-browser` equivalents, viewport error codes |
| [references/snapshot-refs.md](references/snapshot-refs.md) | Ref lifecycle and stale-ref troubleshooting |
| [references/authentication.md](references/authentication.md) | Login/OAuth/2FA patterns and state save/load |
| [references/session-management.md](references/session-management.md) | Multi-surface isolation and state persistence |
| [references/video-recording.md](references/video-recording.md) | Recording status and practical alternatives |
| [references/proxy-support.md](references/proxy-support.md) | Proxy behavior in WKWebView and workarounds |

## Ready-to-use templates

| Template | Description |
|----------|-------------|
| [templates/form-automation.sh](templates/form-automation.sh) | Snapshot/ref form fill loop |
| [templates/authenticated-session.sh](templates/authenticated-session.sh) | Login once, save/load state |
| [templates/capture-workflow.sh](templates/capture-workflow.sh) | Navigate and capture snapshots/screenshots |
