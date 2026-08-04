---
name: zerocmux-debugging
description: "Debug logging, Debug menu, runtime pitfalls, typing-latency-sensitive paths, SwiftUI list snapshot boundaries, OS-version repros, and local visual iteration for zerocmux. Use when adding debug probes, diagnosing UI/runtime issues, touching terminal rendering, tab/sidebar list views, drag/drop UTTypes, or using the Debug menu."
---

# zerocmux Debugging

## Debug event log

Put debug event instrumentation (keys, mouse, focus, splits, tabs) in the unified DEBUG build log. This is not a requirement to log every new code path; most probes belong to a dogfood debug loop and are removed before merge.

```bash
tail -f "$(cat /tmp/zerocmux-last-debug-log-path 2>/dev/null || echo /tmp/zerocmux-debug.log)"
```

- Untagged Debug app: `/tmp/zerocmux-debug.log`
- Tagged Debug app (`./scripts/reload.sh --tag <tag>`): `/tmp/zerocmux-debug-<tag>.log`
- `reload.sh` writes the current path to `/tmp/zerocmux-last-debug-log-path`
- `reload.sh` writes the selected dev CLI path to `/tmp/zerocmux-last-cli-path`
- `reload.sh` updates `/tmp/zerocmux-cli` and `$HOME/.local/bin/zerocmux-dev` to that CLI
- Implementation: `Packages/macOS/CMUXDebugLog/Sources/CMUXDebugLog/DebugEventLog.swift`
- App shim: `Sources/App/DebugLogging.swift`
- Free function `cmuxDebugLog("message")` logs with timestamp and appends to file in real time from zerocmux code
- The package implementation and app shim are `#if DEBUG`; all call sites must be wrapped in `#if DEBUG` / `#endif`
- 500-entry ring buffer; `CMUXDebugLog.DebugEventLog.shared.dump()` writes full buffer to file
- Key events logged in `AppDelegate.swift` (monitor, performKeyEquivalent)
- Mouse/UI events logged inline in views (ContentView, BrowserPanelView, etc.)
- Focus events: `focus.panel`, `focus.bonsplit`, `focus.firstResponder`, `focus.moveFocus`
- Bonsplit events: `tab.select`, `tab.close`, `tab.dragStart`, `tab.drop`, `pane.focus`, `pane.drop`, `divider.dragStart`

## Debug menu

DEBUG builds get a **Debug** menu in the macOS menu bar. When the user says "debug menu" or "debug window" they mean this, not `defaults write`.

**Debug > Debug Windows** holds panels for tuning layout, colors, and behavior, listed alphabetically with no dividers. To add one: create an `NSWindowController` subclass with a `shared` singleton, register it in the "Debug Windows" menu in `Sources/cmuxApp.swift`, and back it with a SwiftUI view using `@AppStorage` bindings for live changes.

## Runtime pitfalls

- Custom drag-and-drop UTTypes must be declared in `Resources/Info.plist` under `UTExportedTypeDeclarations`.
- Do not add an app-level display link or manual `ghostty_surface_draw` loop; rely on Ghostty wakeups/renderer to avoid typing lag.
- `WindowTerminalHostView.hitTest()` in `Sources/TerminalWindowPortal.swift` runs on every event including keyboard. Add no work outside the `isPointerEvent` guard.
- `TabItemView` in `Sources/ContentView.swift` uses `Equatable` plus `.equatable()` to skip body re-evaluation during typing. Do not add environment/store/binding reads without updating `==` and keeping `.equatable()` at the call site.
- `TerminalSurface.forceRefresh()` in `Sources/GhosttyTerminalView.swift` runs on every keystroke. No allocations, file I/O, or formatting.
- `SurfaceSearchOverlay` must be mounted from `GhosttySurfaceScrollView` in `Sources/GhosttyTerminalView.swift`, not from SwiftUI panel containers.
- Views below a `LazyVStack` / `LazyHStack` / `List` / `ForEach` boundary receive immutable snapshots plus closures, never an observable store.
- Functions called from SwiftUI `body` must not mutate state or schedule store writes.
- Foundation, SwiftUI, AttributeGraph, and WebKit semantics change between macOS majors. Test on the reporter's macOS before declaring a user repro disproven.

## Detailed references

- [references/debug-event-log.md](references/debug-event-log.md): when to add probes and how to name them.
- [references/runtime-pitfalls.md](references/runtime-pitfalls.md): read before touching terminal rendering, hit testing, tab rows, list virtualization, search overlay layering, or OS-version-sensitive code.
