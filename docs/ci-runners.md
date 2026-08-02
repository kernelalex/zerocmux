# CI runners

Always-on CI runs on Depot and GitHub-hosted runners only. Linux x64 jobs use
`depot-ubuntu-24.04`; macOS jobs use `depot-macos-26` for every lane, including
`release-build` in `ci.yml` and release signing in `release.yml`. No Linux ARM
lane exists today; when one is added it should use `depot-ubuntu-24.04-arm-4`.
The `ci-macos-compat.yml` matrix runs its single row on `depot-macos-26`
(restore a spread if older-OS coverage becomes available on Depot), and
`cmux-tui.yml` keeps its Windows-experimental lane on GitHub-hosted
`windows-latest` (no Depot mapping requested for Windows). `warp-*` and
`blacksmith-*` labels are never used for always-on lanes and remain manual
break-glass or `workflow_dispatch` choices only.

A few lanes route through repository variables so a runner type can be
switched with a single variable update that takes effect on the next workflow
run, with no PR or commit:

| Variable | Used by | Fallback baked into the workflow |
| ------------------- | ---------------------------------------------------------- | -------------------------------- |
| `LINUX_RUNNER`      | `ci.yml` `linux-preflight`, the `cmux-tui.yml` Linux lanes, and the `cmux-tui-sdks.yml` / `cmux-tui-spec.yml` jobs | `depot-ubuntu-24.04` |
| `MACOS_RUNNER_15`   | manual `test-e2e.yml` / `perf-activation.yml` `auto` runs; the `cmux-tui.yml` macOS row | `depot-macos-26` |
| `MACOS_RUNNER_DUAL_XCODE` | `ci.yml` `swift-package-tests` (builds the SDK 15 Ghostty CLI helper, then runs the SDK 26 package tests in the same job) | `depot-macos-26` |

Workflows reference them as
`runs-on: ${{ vars.LINUX_RUNNER || 'depot-ubuntu-24.04' }}`. If a variable is
unset the job uses the fallback, so CI is never broken by a missing variable.

The remaining `ci.yml` jobs are deliberately hard-pinned to Depot labels:
`workflow-guard-tests`, `app-host-unit-tests`, `tests-build-and-lag`,
`ui-regressions`, and `release-build` on `depot-macos-26`; and the Linux jobs
(`changes`, `remote-daemon-tests`, `react-apps-check`, `diff-sidecar-check`,
`tests`, `agent-session-web-resources`, `ci-status`) on `depot-ubuntu-24.04`.
There is no standalone `release-ghostty-cli-helper` job in `ci.yml` — the
Ghostty CLI helper is built inside `swift-package-tests` there, and by
`build-ghostty-cli-helper` in `release.yml`.

## Break-glass: switch a runner type off Depot

We do not auto-overflow. If Depot is genuinely down or queuing for minutes
(not a sub-minute queue), manually flip the affected variable to an explicit
cloud label; revert it once Depot recovers. Use Depot (default):

```bash
gh variable set LINUX_RUNNER            --repo kernelalex/zerocmux -b depot-ubuntu-24.04
gh variable set MACOS_RUNNER_15         --repo kernelalex/zerocmux -b depot-macos-26
gh variable set MACOS_RUNNER_DUAL_XCODE --repo kernelalex/zerocmux -b depot-macos-26
```

Break-glass a type to another cloud provider only when Depot is down or
queuing for minutes. **Set an explicit cloud label.** Never set any runner
variable to a fleet/self-hosted label.

```bash
gh variable set LINUX_RUNNER    --repo kernelalex/zerocmux -b warp-ubuntu-latest-x64-4x
gh variable set MACOS_RUNNER_15 --repo kernelalex/zerocmux -b warp-macos-15-arm64-6x
```

Check current values:

```bash
gh variable list --repo kernelalex/zerocmux
```

## Manual runs

`perf-activation.yml` and `test-e2e.yml` keep a `runner` choice input that
defaults to `auto`. Manual `auto` runs follow `MACOS_RUNNER_15` then the
`depot-macos-26` fallback, so flipping the repo variable redirects those
workflows. An explicit manual choice wins over the variable; both dropdowns
expose `depot-macos-*` and Warp choices, with a Depot identity guard for
GUI-activation runs. `test-e2e.yml` also exposes `tart-canary`, `tart-dual`,
and `tart-small` for targeted isolated-VM validation. These choices are
available only through `workflow_dispatch`; no always-on lane uses them.

## Guards

Two guard tests (both run by the `workflow-guard-tests` job) enforce the
policy:

- `tests/test_ci_self_hosted_guard.sh` pins the expensive macOS lanes to the
  sanctioned Depot runner: `app-host-unit-tests`, `tests-build-and-lag`,
  `ui-regressions`, and `release-build` in `ci.yml`, `build-ghosttykit` in
  `build-ghosttykit.yml`, the `ci-macos-compat.yml` matrix row, and
  `build-ghostty-cli-helper` plus `build-sign-notarize` in `release.yml`, all
  on `depot-macos-26`. It also fails CI if any always-on workflow hardcodes a
  `warp-*` or `blacksmith-*` runner label — those providers stay manual
  break-glass only.
- `tests/test_ci_release_sdk_lane.sh` pins the release helper handoff lanes
  (`build-ghostty-cli-helper` in `release.yml`, `release-build` and the
  dual-Xcode `swift-package-tests` fallback in `ci.yml`) to `depot-macos-26`.

Keep new labels in `.github/actionlint.yaml`.

## No self-hosted mac-mini fleet in CI

We do not route CI to the persistent self-hosted mac-mini fleet
(`zerocmux-mac-mini`, `studio1`, `mac4-cmuxvnc*`, `zerocmux-austin-mini-*`) for
any job. Those minis carry labels that collide with cloud labels (notably
`macos-26` and `warp-macos-26-arm64-6x`), and GitHub prefers a matching
self-hosted runner, so a required job could silently land on a mini that cannot
foreground a GUI app. It stays `Running Background`, breaking key-window,
pasteboard, IME, and XCUITest behavior. Every macOS lane therefore routes to
Depot or a GitHub-hosted runner, and the guard above fails CI if an always-on
workflow hardcodes a third-party self-hosted-colliding label.

Residual: the guard checks workflow literals, not repo-variable values. Do not
set `MACOS_RUNNER_*` / `LINUX_RUNNER` to a self-hosted label; keep them on
Depot. Fully closing the variable-value path requires removing the colliding
labels from the minis (runner-side, needs org/runner admin).
