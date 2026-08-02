# Authentication Patterns

Login flows, session persistence, OAuth, and 2FA patterns for zerocmux browser surfaces.

## Basic login

```bash
zerocmux browser open https://app.example.com/login --json
zerocmux browser surface:7 wait --load-state complete --timeout-ms 15000

zerocmux browser surface:7 snapshot --interactive
# [ref=e1] email, [ref=e2] password, [ref=e3] submit

zerocmux browser surface:7 fill e1 "user@example.com"
zerocmux browser surface:7 fill e2 "$APP_PASSWORD"
zerocmux browser surface:7 click e3 --snapshot-after --json
zerocmux browser surface:7 wait --url-contains "/dashboard" --timeout-ms 20000
```

## Saving authentication state

```bash
zerocmux browser surface:7 state save ./auth-state.json
```

State includes cookies, localStorage, sessionStorage, and open tab metadata for that surface.

## Restoring authentication

```bash
zerocmux browser open https://app.example.com --json
zerocmux browser surface:8 state load ./auth-state.json
zerocmux browser surface:8 goto https://app.example.com/dashboard
zerocmux browser surface:8 snapshot --interactive
```

## OAuth / SSO

Same shape as basic login, waiting on the provider host and then the return host, with generous timeouts:

```bash
zerocmux browser open https://app.example.com/auth/google --json
zerocmux browser surface:7 wait --url-contains "accounts.google.com" --timeout-ms 30000
zerocmux browser surface:7 snapshot --interactive

zerocmux browser surface:7 fill e1 "user@gmail.com"
zerocmux browser surface:7 click e2 --snapshot-after --json

zerocmux browser surface:7 wait --url-contains "app.example.com" --timeout-ms 45000
zerocmux browser surface:7 state save ./oauth-state.json
```

## Two-factor

```bash
zerocmux browser open https://app.example.com/login --json
zerocmux browser surface:7 snapshot --interactive
zerocmux browser surface:7 fill e1 "user@example.com"
zerocmux browser surface:7 fill e2 "$APP_PASSWORD"
zerocmux browser surface:7 click e3

# complete 2FA manually in the webview, then:
zerocmux browser surface:7 wait --url-contains "/dashboard" --timeout-ms 120000
zerocmux browser surface:7 state save ./2fa-state.json
```

## Cookie-Based Auth

```bash
zerocmux browser surface:7 cookies set session_token "abc123xyz"
zerocmux browser surface:7 goto https://app.example.com/dashboard
```

## Token refresh

Load saved state, navigate, and re-login only when the URL bounced to `/login`:

```bash
#!/usr/bin/env bash
set -euo pipefail
STATE_FILE="./auth-state.json"
SURFACE="surface:7"

if [ -f "$STATE_FILE" ]; then
  zerocmux browser "$SURFACE" state load "$STATE_FILE"
fi

zerocmux browser "$SURFACE" goto https://app.example.com/dashboard
URL=$(zerocmux browser "$SURFACE" get url)

if printf '%s' "$URL" | grep -q '/login'; then
  zerocmux browser "$SURFACE" snapshot --interactive
  zerocmux browser "$SURFACE" fill e1 "$APP_USERNAME"
  zerocmux browser "$SURFACE" fill e2 "$APP_PASSWORD"
  zerocmux browser "$SURFACE" click e3
  zerocmux browser "$SURFACE" wait --url-contains "/dashboard" --timeout-ms 20000
  zerocmux browser "$SURFACE" state save "$STATE_FILE"
fi
```

## Security

Never commit state files; they contain auth tokens. Take credentials from environment variables. Clear state after sensitive tasks:

```bash
zerocmux browser surface:7 cookies clear
rm -f ./auth-state.json
```
