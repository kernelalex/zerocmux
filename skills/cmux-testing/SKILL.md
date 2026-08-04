---
name: zerocmux-testing
description: "zerocmux testing rules for Swift Testing, test target compilation, and package/refactor validation. Use when adding or changing tests, touching package/refactor code, or deciding whether reload.sh is enough validation."
---

# zerocmux Testing

## Regression test commit policy

A regression test for a bug fix ships as two commits so CI proves the test catches the bug:

1. The failing test only, no fix. CI goes red.
2. The fix. CI goes green.

The GitHub PR Commits tab then shows the test genuinely fails without the fix.

## Test wiring

Test files in `cmuxTests/` must be wired into `cmux.xcodeproj/project.pbxproj` with a matching `PBXFileReference` and `PBXSourcesBuildPhase` entry. A `.swift` file added without them is silently ignored by Xcode: `xcodebuild test -only-testing:cmuxTests/<TestClass>` and bot reviews both pass with "Executed 0 tests", so the missing wiring is indistinguishable from a clean red/green regression test until a real user hits the bug. Surfaced during https://github.com/manaflow-ai/cmux/issues/4529 against https://github.com/manaflow-ai/cmux/pull/4536.

The `workflow-guard-tests` CI job runs `./scripts/lint-pbxproj-test-wiring.sh`. Add the file through Xcode (drag into the cmuxTests target) or hand-edit the pbxproj entries using a wired sibling such as `cmuxTests/TabManagerUnitTests.swift` as the template.

## Test quality policy

- No tests that only verify source text, method signatures, AST fragments, or grep-style patterns.
- No tests that read checked-in metadata or project files (`Resources/Info.plist`, `project.pbxproj`, `.xcconfig`, source files) just to assert a key, string, plist entry, or snippet exists.
- Tests verify observable runtime behavior through executable paths (unit, integration, e2e, CLI), not implementation shape.
- For metadata changes, verify the built app bundle or the runtime behavior that depends on the metadata.
- If a behavior cannot be exercised end to end yet, add a small runtime seam or harness first, then test through it.
- If no meaningful behavioral or artifact-level test is practical, skip the fake regression test and say so.

## Test framework

Swift Testing (Swift 6 / Xcode 16) is the default for every unit and integration test: `import Testing`, `@Test`, `@Suite`, `#expect(...)`, `try #require(...)`. Do not write new `import XCTest` tests except UI tests.

- **UI tests stay on XCTest/XCUITest.** Swift Testing has no `XCUIApplication` integration. Files under `cmuxUITests/` keep `XCTestCase`; do not migrate or bridge them.
- **New test targets start on Swift Testing.** Every new package's `Tests/<Name>Tests/` ships with it from the first commit; Xcode 16 auto-detects the framework from `import Testing` with no `Package.swift` configuration.
- **Parameterized tests** use `@Test(arguments: [...])` instead of duplicate methods.
- **Parallelization.** Swift Testing runs tests in parallel by default, including across suites. A suite that needs ordering or guards shared mutable state gets `.serialized`, not locks or sleeps.
- **Tags** via `@Test(.tags(.something))` let CI and local runs filter selectively.
- Migrate an existing XCTest file in place only when an edit already crosses it. Mapping in [references/swift-testing-migration.md](references/swift-testing-migration.md).

## Test target validation

`reload.sh` does not compile the test target. It builds only the `zerocmux` scheme, so a green `reload.sh` says nothing about whether `cmuxTests`/`cmuxUITests` still compile. A symbol that is moved or renamed can keep the `zerocmux` app building while breaking the test target (real case: a `write(to:atomically:)` typo and a removed `TabManager.CommandResult` only surfaced in the `tests` job). Before pushing package/refactor changes, build the `zerocmux-unit` scheme (with `-derivedDataPath /tmp/zerocmux-<tag>` and, for `cmuxApp`/`AppDelegate` churn, the GlobalISel workaround flag) or let the `tests` CI job gate it — never treat `reload.sh` alone as proof the tests build.

## Remote-tmux live layout fuzz

The remote-tmux mirror has a live fuzz: the real app mirroring a real tmux
server, driven with random layouts and churn, judged at settle by two
oracles — sizing (claims, plans, and rendered grids agree, settle within
budget) and content (each pane's `read-screen`, unwrapped, matches
`tmux capture-pane -J`). Seeds are deterministic: the same seed replays the
same op sequence, so "seed 3, iteration 1" in a commit message is a
complete repro recipe.

Everything runs against a local fixture, on any machine, with no real
network and no MFA.

Use the dedicated fuzz alias `cmux-fuzzhost`, and stand it up first:

```
scripts/remote-tmux-fuzz-host.sh cmux-fuzzhost   # loopback-only sshd, isolated tmux
CMUX_TAG=<tag> scripts/remote-tmux-fuzz-marathon.sh cmux-fuzzhost [seeds] [iters]
```

The host script generates a loopback sshd whose logins land in an isolated
`TMUX_TMPDIR` the harness owns, so it can create and kill that tmux lab
freely. Use `cmux-fuzzhost` — **not** `cmux-srvA`/`cmux-srvB`. Those are the
render-harness/interactive loopback aliases: their `/tmp/cmux-srv*` holds a
live interactive tmux the fuzz harness refuses to clobber, and their tmux
dir isn't where the app's `ssh-tmux` connects, so the mirror comes up empty.

`scripts/remote-tmux-live-fuzz.sh cmux-fuzzhost <seed> <iters>` replays one
seed against a running tagged app — the way to reproduce a specific
commit's failure. Seeds are deterministic, so "seed 3, iteration 1" is a
complete repro.

Run it on a quiet machine and treat load as part of the result: settle
budgets are latency assertions, and a loaded box manufactures failures that
read like code bugs.

**Run it once and let it finish.** Launch in the background (or a plain
terminal) and wait — never inside a tmux session (the per-seed reset runs
`tmux kill-server`, which inside tmux hits your default server), and don't
kill the wrapper mid-run: that orphans the driver, which then blocks the
next run. Both scripts allow only one driver at a time.

Setup failures and their fixes (the message tells you which):

- `no workspace mirroring session 'fuzz'` — wrong host. The fuzz session's
  tmux dir isn't where `ssh-tmux <alias>` connects, so the app mirrored the
  default shell instead. Use `cmux-fuzzhost`.
- `refusing to kill an unowned lab` — a stale lab tmux from an aborted run
  or a manual `ssh cmux-fuzzhost` probe. Kill it scoped to that dir:
  `TMUX_TMPDIR=<host's fuzz tmux dir> tmux kill-server` (never a bare
  `kill-server`).
- `another fuzz driver (pid N) is running` — a prior or orphaned driver
  still holds the lock. `pkill -9 -f remote-tmux-fuzz-marathon.sh;
  pkill -9 -f remote-tmux-live-fuzz.sh`, then remove the
  `cmux-fuzz-marathon.lock` directory under the temp root.
- ssh to the alias shows `REMOTE HOST IDENTIFICATION HAS CHANGED` or
  `no such identity` — the host script was re-run and regenerated the
  sshd host key / relocated the client key. Clear the stale host key with
  `ssh-keygen -R "[127.0.0.1]:<port>"`, and make sure the alias's
  `IdentityFile` points at the key the script actually wrote.

## Detailed references

- Read [references/swift-testing-migration.md](references/swift-testing-migration.md) when converting XCTest unit tests to Swift Testing or adding new package tests.
- Read [references/regression-and-quality.md](references/regression-and-quality.md) when adding a regression test, deciding whether a test is behavioral enough, or checking Xcode project test wiring.
- Read [references/local-vs-ci-validation.md](references/local-vs-ci-validation.md) when choosing between `reload.sh`, `zerocmux-unit`, GitHub Actions, E2E/UI tests, and Python socket tests.
- Read [references/remote-tmux-sizing-e2e.md](references/remote-tmux-sizing-e2e.md) when working on remote-tmux mirror sizing, the sizing UI-test suite, its ssh shim, or the `remote.tmux.pane_grids` / `remote.tmux.test_exec` debug verbs.
