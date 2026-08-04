# Proxy Support

How proxy behavior works for zerocmux browser automation.

There is no `cmux browser proxy ...` command for per-surface routing: WKWebView has no CDP-style per-context proxy controls. Configure a system or network-level proxy for the environment cmux runs in, or route traffic through an upstream gateway you control.

## Contents

- [Current Behavior](#current-behavior)
- [What Is Not Exposed via CLI](#what-is-not-exposed-via-cli)
- [Workarounds](#workarounds)
- [Verification](#verification)

## Current Behavior

zerocmux browser uses WKWebView networking. Proxy behavior follows macOS/system networking and app process environment.

## What Is Not Exposed via CLI

There is currently no first-class `zerocmux browser proxy ...` command for per-surface proxy routing.

Why: WKWebView does not provide CDP-style per-context proxy controls equivalent to Chrome automation stacks.

## Workarounds

1. Configure system/network-level proxy for the environment where zerocmux runs.
2. Route traffic through an upstream gateway you control.
3. Validate behavior with explicit IP checks.

## Verification

```bash
zerocmux browser open https://httpbin.org/ip --json
zerocmux browser surface:7 get text body
```
