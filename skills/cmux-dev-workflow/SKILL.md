---
name: zerocmux-dev-workflow
description: "Contributor workflow rules for zerocmux setup, Xcode project normalization, tagged sidebar ExtensionKit development, and dev builds. Use when setting up the zerocmux repo, changing Xcode project files, adding sidebar extensions, or working with tagged debug builds."
---

# zerocmux Dev Workflow

## Initial setup

`./scripts/setup.sh` initializes submodules, builds GhosttyKit, and installs the pbxproj normalization pre-commit hook.

## Tagged local dev

Build the Debug app after every code change:

```bash
./scripts/reload.sh --tag <short-tag>
```

It builds without launching; pass `--launch` only when you need the app open. Never run bare `xcodebuild` or open an untagged `cmux DEV.app`: untagged builds share the default debug socket and bundle ID with other agents, causing conflicts and stealing focus.

Never run bare `xcodebuild` or open an untagged `zerocmux DEV.app`. Untagged builds share the default debug socket and bundle ID with other agents, causing conflicts and stealing focus.

For CLI or socket dogfood against a tagged Debug app, use the tag-bound helper and set `CMUX_TAG`:

```bash
CMUX_TAG=<tag> scripts/zerocmux-debug-cli.sh list-workspaces
```

Do not use `/tmp/zerocmux-cli` for tagged dogfood. That symlink points at the most recently reloaded build.

When rebuilding cmuxd for release/bundling, always use ReleaseFast:

```bash
cd cmuxd && zig build -Doptimize=ReleaseFast
```

## Initial setup

Run the setup script to initialize submodules, build GhosttyKit, and install the pbxproj normalization pre-commit hook:

```bash
./scripts/setup.sh
```

## Xcode toolchain

The team is pinned to Xcode 26.x. `.xcode-version` records the major; `cmux.xcodeproj/project.pbxproj` carries `objectVersion = 60`, which is what Xcode 26 writes by default. (objectVersion 77 is reserved for projects that adopt synchronized folder groups, which zerocmux does not use yet. Bumping to a different value requires a deliberate team decision.)

`scripts/setup.sh` installs the tracked `scripts/git-hooks/pre-commit`, which runs `scripts/normalize-pbxproj.py` on any staged `project.pbxproj` so Xcode's nondeterministic reordering never reaches a commit. The hook is idempotent. CI runs `scripts/check-pbxproj.sh` to enforce both the `objectVersion` pin and normalization, so skipping the hook gives a clear PR failure. Bumping the pin is a deliberate team decision: see [references/xcode-project-normalization.md](references/xcode-project-normalization.md).

## Sidebar extension point (dev tagging)

Each tagged dev build gets its own ExtensionKit sidebar extension point so concurrent dev builds do not collide. Three build settings drive it:

- `CMUX_SIDEBAR_EXTENSION_POINT_ID` (default `com.kernelalex.zerocmux.cmux.sidebar`): the extension point identifier baked into Info.plist at build time.
- `CMUX_BUNDLE_ID_SUFFIX` (default empty): inserted into the app and appex bundle ids so a tagged extension gets a distinct identity that pkd records separately.
- `CMUX_DISPLAY_NAME_SUFFIX` (default empty): appended to the appex `CFBundleDisplayName`. The OS groups sidebar extensions by display name for the enable/disable + availability counts the host reads (`AppExtensionIdentity` exposes only `bundleIdentifier`, `localizedName`, `extensionPointIdentifier`, `id` — zerocmux already keys its own identity off the stable `bundleIdentifier`, but the OS-level grouping is by name). Two same-named appexes installed side by side (a base build and a tagged build) are treated as one logical extension, so toggling one perturbs the other; a per-tag display name keeps them distinct.

The host resolves its point id at runtime from the Info.plist key `CMUXSidebarExtensionPointIdentifier` via `CmuxSidebarExtensionPoint.identifier(in:)`. `./scripts/reload.sh --tag <tag>` scopes the host point to `com.kernelalex.zerocmux.debug.<tag>.cmux.sidebar`. `./scripts/reload-extension.sh --tag <tag> [--host-bundle-id <id>] [--example sample|tabs|both]` builds a matching tag-scoped sample extension, passing `CMUX_SIDEBAR_EXTENSION_POINT_ID=<host-bundle-id>.cmux.sidebar`, `CMUX_BUNDLE_ID_SUFFIX=.<tag>`, and `CMUX_DISPLAY_NAME_SUFFIX=" <tag>"`. It installs exactly what xcodebuild produced (xcodebuild ad-hoc signs with entitlements intact) — it does NOT re-sign, because a bare `codesign --force --sign -` strips the appex entitlements and the extension then drops its host XPC connection. pkd ingests the tagged copy because its bundle id is distinct. Verify with `pluginkit -m -p <host-bundle-id>.cmux.sidebar`.

```bash
./scripts/reload-extension.sh --tag <tag> [--host-bundle-id <id>] [--example sample|tabs|both]
```

- appex Info.plist: `EXAppExtensionAttributes:EXExtensionPointIdentifier = $(CMUX_SIDEBAR_EXTENSION_POINT_ID)`.
- add `CMUX_SIDEBAR_EXTENSION_POINT_ID` (default `com.kernelalex.zerocmux.cmux.sidebar`), `CMUX_BUNDLE_ID_SUFFIX` (default empty), and `CMUX_DISPLAY_NAME_SUFFIX` (default empty) build settings to the app and appex targets in all build configs.
- `PRODUCT_BUNDLE_IDENTIFIER` = `<appBase>$(CMUX_BUNDLE_ID_SUFFIX)` for the app target and `<appBase>$(CMUX_BUNDLE_ID_SUFFIX).<leaf>` for the appex (suffix before the appex leaf so the appex id stays prefixed by the app id).
- appex `INFOPLIST_KEY_CFBundleDisplayName` (or the `CFBundleDisplayName` Info.plist value) = `<Name>$(CMUX_DISPLAY_NAME_SUFFIX)`.
- it must be ad-hoc signed by xcodebuild (Info.plist bound, entitlements intact) for pkd to ingest the tagged copy; do not re-sign post-build.

## Detailed references

- Read [references/tagged-builds.md](references/tagged-builds.md) for detailed tagged reload, app link, socket, and cleanup behavior.
- Read [references/xcode-project-normalization.md](references/xcode-project-normalization.md) before touching `.xcode-version` or `cmux.xcodeproj/project.pbxproj`.
- Read [references/sidebar-extension-tagging.md](references/sidebar-extension-tagging.md) when changing ExtensionKit sidebar extension identifiers, tagged sample extensions, or `pluginkit` verification.
