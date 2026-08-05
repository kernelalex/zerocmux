# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

zerocmux (formerly zerocmux) is a native macOS Swift/AppKit terminal workspace built
on libghostty, with workspace tabs, split panes, an in-app browser, OSC-based
notifications, and a CLI/socket automation surface. `README.md` and `AGENTS.md`
have product-level details; this file is the operational guide for agents.

## High-level layout

- `Sources/` — main app target (Xcode project `cmux.xcodeproj`,
  scheme `zerocmux`). Subfolders: `App/`, `Auth/`, `Cloud/`, `CommandPalette/`,
  `Feed/`, `Find/`, `Panels/` (terminal/browser/file/markdown panes),
  `Settings/`, `Sidebar/`, `Update/`, `Windowing/`. Top-level files cover
  workspace/tab/split state, socket commands, event bus, and AppleScript.
- `Packages/` — local SwiftPM modules consumed by the app target:
  `CMUXAgentLaunch`, `CMUXAgentVault`, `CMUXDebugLog`, `CMUXPasteboardFidelity`,
  `CMUXWorkstream`. Move reusable, UI-independent logic here.
- `CLI/` — the `zerocmux` CLI that talks to the running app over a unix
  socket (`/tmp/zerocmux.sock`, or `/tmp/zerocmux-debug-<tag>.sock` for tagged builds).
- `cmux-tui/` — local Rust TUI multiplexer (adopted from upstream) with a
  JSON-lines local control socket; its CI lane is
  `.github/workflows/cmux-tui.yml`.
- `agent-chat/` — loopback-only, token-protected agent-chat sidecar. There is
  no remote model catalog; models come from built-in lists plus installed
  agent CLIs.
- `cmuxTests/` — Swift unit tests (scheme `zerocmux-unit`).
- `cmuxUITests/` — XCUITest UI tests (run on the cmux-vm via CI).
- `tests/` and `tests_v2/` — Python regression suites that drive the app
  through its CLI/socket. v2 is the active surface; v1 is legacy.
- `ghostty/` (submodule, fork at `manaflow-ai/ghostty`) — produces
  `GhosttyKit.xcframework` via `zig build`.
- `vendor/bonsplit/` (submodule) — split-pane tab-bar engine used by workspaces.
- `Resources/` — Info.plist, `Localizable.xcstrings`, asset catalogs.
- `scripts/` — build/release/test orchestration (`reload*.sh`, `setup.sh`,
  `bump-version.sh`, `release-pretag-guard.sh`, `run-tests-v*.sh`, `run-e2e.sh`).
- `docs/` — design specs (CLI contract, events, agent hooks, vault, dock, etc.).

## Architecture notes that span files

- The app, CLI, and Python tests share a single line-protocol over the unix
  socket. New behaviors usually mean: a socket command handler in `Sources/`,
  a CLI subcommand in `CLI/`, and a `tests_v2/test_*.py` regression. See the
  Shared behavior policy below before patching one surface in isolation.
- Workspaces hold tabs; tabs hold a `bonsplit` tree of panes; each pane hosts
  a Panel (`TerminalPanel`, `BrowserPanel`, `FilePreviewPanel`,
  `MarkdownPanel`). Routing focus/drag/keys correctly across the
  AppKit-portal/SwiftUI boundary is the source of most subtle bugs — see the
  Pitfalls section.
- Debug-only diagnostics flow through `CMUXDebugLog` (see Debug event log).

## Initial setup

Run the setup script to initialize submodules and build GhosttyKit:

```bash
./scripts/setup.sh
```

## Local dev

After making code changes, always run the reload script with a tag to build the Debug app:

```bash
./scripts/reload.sh --tag fix-zsh-autosuggestions
```

By default, `reload.sh` builds but does **not** launch the app. The script prints the `.app` path so the user can cmd-click to open it. After a successful build, it always terminates any running app with the same tag (so cmd-clicking launches the freshly-built binary instead of foregrounding the stale instance). Pass `--launch` to open the app automatically after the build:

```bash
./scripts/reload.sh --tag fix-zsh-autosuggestions --launch
```

`reload.sh` prints an `App path:` line with the absolute path to the built `.app`. Use that path to build a cmd-clickable `file://` URL. Steps:

1. Grab the path from the `App path:` line in `reload.sh` output.
2. Prepend `file://` and URL-encode spaces as `%20`. Do not hardcode any part of the path.
3. Format it as a markdown link using the template for your agent type.

Example. If `reload.sh` output contains:
```
App path:
  /Users/someone/Library/Developer/Xcode/DerivedData/zerocmux-my-tag/Build/Products/Debug/zerocmux DEV my-tag.app
```

**Claude Code** outputs:
```markdown
=======================================================
[zerocmux DEV my-tag.app](file:///Users/someone/Library/Developer/Xcode/DerivedData/zerocmux-my-tag/Build/Products/Debug/zerocmux%20DEV%20my-tag.app)
=======================================================
```

**Codex** outputs:
```
=======================================================
[my-tag: file:///Users/someone/Library/Developer/Xcode/DerivedData/zerocmux-my-tag/Build/Products/Debug/zerocmux%20DEV%20my-tag.app](file:///Users/someone/Library/Developer/Xcode/DerivedData/zerocmux-my-tag/Build/Products/Debug/zerocmux%20DEV%20my-tag.app)
=======================================================
```

Never use `/tmp/zerocmux-<tag>/...` app links in chat output.

For CLI or socket dogfood against a tagged Debug app, use the tag-bound helper and set `CMUX_TAG`.
Do not use `/tmp/zerocmux-cli` for tagged dogfood, since that symlink points at the most recently
reloaded build and can target the user's main app socket.

```bash
CMUX_TAG=<tag> scripts/zerocmux-debug-cli.sh list-workspaces
CMUX_TAG=<tag> scripts/zerocmux-debug-cli.sh send --workspace workspace:1 --surface surface:1 "echo ok"
```

The helper refuses to run without `CMUX_TAG`, targets `/tmp/zerocmux-debug-<tag>.sock`, and uses
the matching tagged CLI from `~/Library/Developer/Xcode/DerivedData/zerocmux-<tag>/...`. It also
scrubs ambient terminal context (`CMUX_SOCKET`, `CMUX_SOCKET_PASSWORD`, workspace/surface/tab/panel
IDs, cmuxd socket, and debug log), then sets `CMUX_SOCKET_PATH`, `CMUX_BUNDLE_ID`, and
`CMUX_BUNDLED_CLI_PATH` for the selected tag.

After making code changes, always use `reload.sh --tag` to build. **Never run bare `xcodebuild` or `open` an untagged `zerocmux DEV.app`.** Untagged builds share the default debug socket and bundle ID with other agents, causing conflicts and stealing focus.

```bash
./scripts/reload.sh --tag <your-branch-slug>
```

If you only need to verify the build compiles (no launch), use a tagged derivedDataPath:

```bash
xcodebuild -project cmux.xcodeproj -scheme zerocmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/zerocmux-<your-tag> build
```

When rebuilding GhosttyKit.xcframework, always use Release optimizations:

```bash
cd ghostty && zig build -Demit-xcframework=true -Dxcframework-target=universal -Doptimize=ReleaseFast
```

`reload` = build the Debug app (tag required) and terminate any running app with the same tag. Pass `--launch` to also open the freshly-built app:

```bash
./scripts/reload.sh --tag <tag>
./scripts/reload.sh --tag <tag> --launch
```

`reloadp` = kill and launch the Release app:

```bash
./scripts/reloadp.sh
```

`reloads` = kill and launch the Release app as "zerocmux STAGING" (isolated from production zerocmux):

```bash
./scripts/reloads.sh
```

`reload2` = reload both Debug and Release (tag required for Debug reload):

```bash
./scripts/reload2.sh --tag <tag>
```

For parallel/isolated builds (e.g., testing a feature alongside the main app), use `--tag` with a short descriptive name:

```bash
./scripts/reload.sh --tag fix-blur-effect
```

This creates an isolated app with its own name, bundle ID, socket, and derived data path so it runs side-by-side with the main app. Important: use a non-`/tmp` derived data path if you need xcframework resolution (the script handles this automatically).

Before launching a new tagged run, clean up any older tags you started in this session (quit old tagged app + remove its `/tmp` socket/derived data).

## Web app

zerocmux does not ship the upstream Next.js web app or hosted Cloud VM backend.
Do not add Vercel, Stack Auth, Cloud VM provider, or `web/` workflow changes
unless a future architecture decision explicitly restores that surface.
Upstream's top-level `vault/` (cmux Vault cloud sync) is excluded as well —
the fork's `CMUXAgentVault` package and `VaultAgentRegistry` are unrelated
local features.

## Debug event log

When adding debug event instrumentation, put events (keys, mouse, focus, splits, tabs)
in the unified DEBUG build log:

This section describes the required destination and shape for debug logs when they
are added. It is not a blanket requirement to add debug logs to every new code path.
Most temporary probes should be added only during the dogfood debug loop and removed
before merge.

```bash
tail -f "$(cat /tmp/zerocmux-last-debug-log-path 2>/dev/null || echo /tmp/zerocmux-debug.log)"
```

- Untagged Debug app: `/tmp/zerocmux-debug.log`
- Tagged Debug app (`./scripts/reload.sh --tag <tag>`): `/tmp/zerocmux-debug-<tag>.log`
- `reload.sh` writes the current path to `/tmp/zerocmux-last-debug-log-path`
- `reload.sh` writes the selected dev CLI path to `/tmp/zerocmux-last-cli-path`
- `reload.sh` updates `/tmp/zerocmux-cli` and `$HOME/.local/bin/zerocmux-dev` to that CLI, plus legacy `zerocmux` aliases

- Implementation: `Packages/CMUXDebugLog/Sources/CMUXDebugLog/DebugEventLog.swift`
- App shim: `Sources/App/DebugLogging.swift`
- Free function `cmuxDebugLog("message")` — logs with timestamp and appends to file in real time from zerocmux code
- The package implementation and app shim are `#if DEBUG`; all call sites must be wrapped in `#if DEBUG` / `#endif`
- 500-entry ring buffer; `CMUXDebugLog.DebugEventLog.shared.dump()` writes full buffer to file
- Key events logged in `AppDelegate.swift` (monitor, performKeyEquivalent)
- Mouse/UI events logged inline in views (ContentView, BrowserPanelView, etc.)
- Focus events: `focus.panel`, `focus.bonsplit`, `focus.firstResponder`, `focus.moveFocus`
- Bonsplit events: `tab.select`, `tab.close`, `tab.dragStart`, `tab.drop`, `pane.focus`, `pane.drop`, `divider.dragStart`

## Regression test commit policy

When adding a regression test for a bug fix, use a two-commit structure so CI proves the test catches the bug:

1. **Commit 1:** Add the failing test only (no fix). CI should go red.
2. **Commit 2:** Add the fix. CI should go green.

This makes it visible in the GitHub PR UI (Commits tab, check statuses) that the test genuinely fails without the fix.

## First pass, then dogfood

A task's first pass ends when the change is implemented, the tagged build succeeded on the pushed HEAD, focused tests ran, and the PR is open. Then hand off to the user for dogfood. Do not fix CI failures, merge conflicts, or review findings inline in the main conversation after that point.

At handoff, launch one background `$autoreview` subagent with a bounded prompt (PR URL, worktree, base ref, allowed write scope, required verification), never a vague "make it green". That loop owns CI: it runs structured review plus PR feedback, and only when a check actually fails does it spawn a bounded repair subagent with that check's name and log context. Do not launch a separate parallel CI repair agent; two agents mutating one worktree race each other. One writer per worktree: if dogfood feedback needs main-agent edits while the loop runs, stop the loop first or give it its own sibling worktree. In Claude Code spawn the loop with the agent/task tool; in Codex use a background sub-task or bounded background `codex exec`.

The loop may commit and push scoped fixes but never merges and never rebuilds the user's tagged build. The main agent inspects every pushed commit, rejects out-of-scope edits, and owns dogfood, approval, and merge. Merging app/runtime/UI changes still requires the user's explicit approval after dogfood; if a pushed fix changes runtime behavior mid-dogfood, rebuild the tag and re-notify, since the earlier verdict covers only the build the user tested.

Notify through `zerocmux notify` so the user can leave and return. At handoff the main agent sends `zerocmux notify --title "Dogfood ready: <short task>" --subtitle "<branch> · <tag>" --body "Was: <prior bad behavior>. Now: <expected behavior>. <concrete check>. CI + review in background. PR: <pr-url>"`. The loop sends its outcome when done or blocked, e.g. `--title "CI green: <branch>"`, `--title "Review clean: <branch>" --body "fixed <n> findings, pushed"`, or `--title "CI blocked: <branch>" --body "<check>: <one-line cause>, needs your decision"`. Titles carry the outcome and branch; bodies say what happened and the single next action. If there is no zerocmux socket, skip notify and rely on the chat handoff.

## Shared behavior policy

- When a behavior is exposed through multiple entrypoints (keyboard shortcut, command palette, context menu, CLI, settings, debug menu), implement one shared action/model path and verify every entrypoint that should invoke it. Do not patch one surface while leaving the others with duplicated logic.
- For optimistic UI or CLI updates, keep one mutation path, record pending state with a request id or previous snapshot, reconcile from the authoritative result, and handle failure with an explicit rollback or error state. Do not let each entrypoint maintain its own optimistic copy.
- When a user says tests missed a bug, add or adjust behavior-level coverage around the exact repro path before claiming the fix is complete.

## Debug menu

The app has a **Debug** menu in the macOS menu bar (only in DEBUG builds). Use it for visual iteration:

- **Debug > Debug Windows** contains panels for tuning layout, colors, and behavior. Entries are alphabetical with no dividers.
- To add a debug toggle or visual option: create an `NSWindowController` subclass with a `shared` singleton, add it to the "Debug Windows" menu in `Sources/cmuxApp.swift`, and add a SwiftUI view with `@AppStorage` bindings for live changes.
- When the user says "debug menu" or "debug window", they mean this menu, not `defaults write`.

## Pitfalls

- **Custom UTTypes** for drag-and-drop must be declared in `Resources/Info.plist` under `UTExportedTypeDeclarations` (e.g. `com.splittabbar.tabtransfer`, `com.cmux.sidebar-tab-reorder`).
- Do not add an app-level display link or manual `ghostty_surface_draw` loop; rely on Ghostty wakeups/renderer to avoid typing lag.
- **Typing-latency-sensitive paths** (read carefully before touching these areas):
  - `WindowTerminalHostView.hitTest()` in `TerminalWindowPortal.swift`: called on every event including keyboard. All divider/sidebar/drag routing is gated to pointer events only. Do not add work outside the `isPointerEvent` guard.
  - `TabItemView` in `ContentView.swift`: uses `Equatable` conformance + `.equatable()` to skip body re-evaluation during typing. Do not add `@EnvironmentObject`, `@ObservedObject` (besides `tab`), or `@Binding` properties without updating the `==` function. Do not remove `.equatable()` from the ForEach call site. Do not read `tabManager` or `notificationStore` in the body; use the precomputed `let` parameters instead.
  - `TerminalSurface.forceRefresh()` in `GhosttyTerminalView.swift`: called on every keystroke. Do not add allocations, file I/O, or formatting here.
- **Terminal find layering contract:** `SurfaceSearchOverlay` must be mounted from `GhosttySurfaceScrollView` in `Sources/GhosttyTerminalView.swift` (AppKit portal layer), not from SwiftUI panel containers such as `Sources/Panels/TerminalPanelView.swift`. Portal-hosted terminal views can sit above SwiftUI during split/workspace churn.
- **Submodule safety:** When modifying a submodule (ghostty, vendor/bonsplit, etc.), always push the submodule commit to its remote `main` branch BEFORE committing the updated pointer in the parent repo. Never commit on a detached HEAD or temporary branch — the commit will be orphaned and lost. Verify with: `cd <submodule> && git merge-base --is-ancestor HEAD origin/main`.
- **All user-facing strings must be localized.** Use `String(localized: "key.name", defaultValue: "English text")` for every string shown in the UI (labels, buttons, menus, dialogs, tooltips, error messages). Keys go in `Resources/Localizable.xcstrings` with translations for all supported languages (currently English and Japanese). Never use bare string literals in SwiftUI `Text()`, `Button()`, alert titles, etc.
- **Shortcut policy:** Every new zerocmux-owned keyboard shortcut must be added to `KeyboardShortcutSettings`, visible/editable in Settings, supported in `~/.config/cmux/cmux.json`, and documented in the keyboard shortcut and configuration docs.
- **Snapshot boundary for list subtrees.** In any SwiftUI panel whose `body` contains a `LazyVStack` / `LazyHStack` / `List` / `ForEach` of rows, no view below that boundary may hold a reference to an `ObservableObject` / `@Observable` store (no `@ObservedObject`, `@EnvironmentObject`, `@StateObject`, `@Bindable`, or even a plain `let store: SomeStore` property). Rows and drop-gaps receive immutable value snapshots plus closure action bundles only. Violating this reintroduces the "orthogonal @Published change invalidates every row and thrashes `LazyLayoutViewCache`" class of 100% CPU spin loop that hit the Sessions panel and the workspace sidebar (https://github.com/kernelalex/zerocmux/issues/2586). Reference pattern: `IndexSectionActions` / `SectionGapActions` / `SessionSearchFn` in `Sources/SessionIndexView.swift`.
- **No state mutation inside view-body computations.** A function called from `body` (directly or through a helper) must not write `@Published` state, schedule a `Task { @MainActor in store.x = … }`, or `DispatchQueue.main.async` a store write. That creates a re-render feedback loop and pegs the main thread (same root-cause family as the snapshot-boundary rule). State-changing work triggered by "new data appeared" belongs in a `reload()` completion, a `didSet`, or a property-observer — never in the projection that feeds `ForEach`.

## Test quality policy

- Do not add tests that only verify source code text, method signatures, AST fragments, or grep-style patterns.
- Do not add tests that read checked-in metadata or project files such as `Resources/Info.plist`, `project.pbxproj`, `.xcconfig`, or source files only to assert that a key, string, plist entry, or snippet exists.
- Tests must verify observable runtime behavior through executable paths (unit/integration/e2e/CLI), not implementation shape.
- For metadata changes, prefer verifying the built app bundle or the runtime behavior that depends on that metadata, not the checked-in source file.
- If a behavior cannot be exercised end-to-end yet, add a small runtime seam or harness first, then test through that seam.
- If no meaningful behavioral or artifact-level test is practical, skip the fake regression test and state that explicitly.

## Socket command threading policy

- Do not use `DispatchQueue.main.sync` for high-frequency socket telemetry commands (`report_*`, `ports_kick`, status/progress/log metadata updates).
- For telemetry hot paths:
  - Parse and validate arguments off-main.
  - Dedupe/coalesce off-main first.
  - Schedule minimal UI/model mutation with `DispatchQueue.main.async` only when needed.
- Commands that directly manipulate AppKit/Ghostty UI state (focus/select/open/close/send key/input, list/current queries requiring exact synchronous snapshot) are allowed to run on main actor.
- If adding a new socket command, default to off-main handling; require an explicit reason in code comments when main-thread execution is necessary.

## Socket focus policy

- Socket/CLI commands must not steal macOS app focus (no app activation/window raising side effects).
- Only explicit focus-intent commands may mutate in-app focus/selection (`window.focus`, `workspace.select/next/previous/last`, `surface.focus`, `pane.focus/last`, browser focus commands, and v1 focus equivalents).
- All non-focus commands should preserve current user focus context while still applying data/model changes.

## Testing policy

**Never run tests locally.** All tests (E2E, UI, python socket tests) run via GitHub Actions or on the VM.

- **E2E / UI tests:** trigger via `gh workflow run test-e2e.yml` (see cmuxterm-hq CLAUDE.md for details)
- **Unit tests:** `./scripts/test-unit.sh` (wraps `xcodebuild -scheme zerocmux-unit`) is safe (no app launch), but prefer CI
- **Python socket tests (tests_v2/):** these connect to a running zerocmux instance's socket. Never launch an untagged `zerocmux DEV.app` to run them. If you must test locally, use a tagged build's socket (`/tmp/zerocmux-debug-<tag>.sock`) with `CMUX_SOCKET_PATH=/tmp/zerocmux-debug-<tag>.sock`
- **Never `open` an untagged `zerocmux DEV.app`** from DerivedData. It conflicts with the user's running debug instance.

## Ghostty submodule workflow

Ghostty changes must be committed in the `ghostty` submodule and pushed to the `manaflow-ai/ghostty` fork.
Keep `docs/ghostty-fork.md` up to date with any fork changes and conflict notes.

```bash
cd ghostty
git remote -v  # origin = upstream, manaflow = fork
git checkout -b <branch>
git add <files>
git commit -m "..."
git push manaflow <branch>
```

To keep the fork up to date with upstream:

```bash
cd ghostty
git fetch origin
git checkout main
git merge origin/main
git push manaflow main
```

Then update the parent repo with the new submodule SHA:

```bash
cd ..
git add ghostty
git commit -m "Update ghostty submodule"
```

## Release

Use the `/release` command to prepare a new release. This will:
1. Determine the new version (bumps minor by default)
2. Gather commits since the last tag and update the changelog
3. Update `CHANGELOG.md`
4. Run `./scripts/bump-version.sh` to update both versions
5. Commit, run `./scripts/release-pretag-guard.sh`, tag, and push

Version bumping:

```bash
./scripts/bump-version.sh          # bump minor (0.15.0 → 0.16.0)
./scripts/bump-version.sh patch    # bump patch (0.15.0 → 0.15.1)
./scripts/bump-version.sh major    # bump major (0.15.0 → 1.0.0)
./scripts/bump-version.sh 1.0.0    # set specific version
```

This updates both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` (build number). The build number is auto-incremented and is required for Sparkle auto-update to work.

Before creating a release tag, run:

```bash
./scripts/release-pretag-guard.sh
```

If it fails, run `./scripts/bump-version.sh`, commit the build-number bump, then retry tagging.

Manual release steps (if not using the command):

```bash
./scripts/release-pretag-guard.sh
git tag vX.Y.Z
git push origin vX.Y.Z
gh run watch --repo Enigma-Labs-Technology/zerocmux
```

Notes:
- Release signing only runs from `v*` tag pushes. Protect the `v*` tag pattern in
  GitHub before publishing.
- The `release` GitHub environment must exist and should require approval before
  secrets are released.
- The release job requires a self-hosted macOS runner with the `zerocmux-signing`
  label.
- The release workflow reads signing material from AWS Secrets Manager via
  GitHub OIDC, not GitHub secrets. Configure GitHub variables:
  `AWS_REGION`, `AWS_RELEASE_ACCOUNT_ID`, `AWS_RELEASE_SIGNING_ROLE_ARN`,
  `AWS_RELEASE_APPLE_SECRET_ARN`, and `AWS_RELEASE_SPARKLE_SECRET_ARN`.
- The AWS IAM role trust policy should allow the GitHub OIDC provider only for
  audience `sts.amazonaws.com` and subject
  `repo:Enigma-Labs-Technology/zerocmux:environment:release`. The `v*` tag
  restriction is enforced by the workflow trigger, protected tags, and the
  `release` environment's deployment rules.
- The AWS IAM role needs `secretsmanager:GetSecretValue` for only the two
  release secret ARNs and `secretsmanager:ListSecrets` for the account. Add
  `kms:Decrypt` for the relevant key if either secret uses a customer-managed
  KMS key.
- `AWS_RELEASE_APPLE_SECRET_ARN` must point to a JSON secret with these keys:
  `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`,
  `APPLE_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`,
  `APPLE_TEAM_ID`, and `APPLE_RELEASE_PROVISIONING_PROFILE_BASE64`.
- `AWS_RELEASE_SPARKLE_SECRET_ARN` must point to a JSON secret with
  `SPARKLE_PRIVATE_KEY`.
- The release asset is `zerocmux-macos.dmg` attached to the tag.
- README download instructions point to GitHub Releases.
- Versioning: bump the minor version for updates unless explicitly asked otherwise.
- Changelog: update `CHANGELOG.md`; docs changelog is rendered from it.

## Skills

Detailed zerocmux contributor rules live in repo skills under `skills/`; use the task-specific skill before changing that area.

Core skill map:

- `cmux-dev-workflow`: setup, tagged reloads, Xcode project normalization, sidebar extension tagging, local dev build isolation.
- `cmux-architecture`: package boundaries, refactor architecture, file/API discipline, testability, Swift concurrency rules.
- `cmux-debugging`: debug event log, Debug menu, runtime pitfalls, typing-sensitive paths, SwiftUI list boundaries.
- `cmux-localization`: user-facing strings, localization files, shortcut text, and localization audit.
- `cmux-testing`: regression policy, Swift Testing, test quality, test wiring, local vs CI validation.
- `cmux-socket-policy`: socket command threading and focus preservation.
- `cmux-shared-behavior`: shared action paths for multi-entrypoint behavior and optimistic updates.
- `cmux-ghostty`: Ghostty submodule and GhosttyKit workflow.
- `cmux-release`: release, version bump, changelog, pretag guard, and release asset workflow.
