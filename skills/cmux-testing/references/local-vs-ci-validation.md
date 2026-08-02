# Local vs CI Validation

## `reload.sh`

Proves the app target built. Proves nothing about `cmuxTests`, `cmuxUITests`, package test targets, or test-only imports. For package/refactor work, treat it as insufficient on its own.

## Unit test target

`xcodebuild -scheme zerocmux-unit` is safe because it does not launch the app. Prefer CI when practical, but use `zerocmux-unit` when package/refactor changes can break tests while the app target still builds.

Use a tagged derived data path:

```bash
xcodebuild -project cmux.xcodeproj -scheme zerocmux-unit -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/zerocmux-<tag> build
```

For `cmuxApp` or `AppDelegate` churn, add the repo's GlobalISel workaround flag if current project instructions require it.

## E2E and UI tests

Run through GitHub Actions or the VM: `gh workflow run test-e2e.yml`. Never launch an untagged app locally to satisfy socket or UI tests.

## Python socket tests

Python socket tests under `tests_v2/` connect to a running zerocmux instance socket. If they must be run locally, use a tagged build socket:

```bash
CMUX_SOCKET_PATH=/tmp/zerocmux-debug-<tag>.sock
```

Never launch or target an untagged `zerocmux DEV.app` for these tests. It can conflict with the user's running debug instance.
