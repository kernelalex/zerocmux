import Foundation
import Observation
import os

struct CmuxFeatureFlagDefinition: Identifiable, Equatable, Sendable {
    var id: String { key }

    let key: String
    let title: String
    let flagDescription: String
    let defaultWhenUnavailable: Bool
}

/// zerocmux: local-only runtime feature flags. The upstream PostHog control
/// plane is removed under the zero-telemetry policy; flags resolve from local
/// overrides and per-flag defaults only, with no network resolution.
///
/// Resolution semantics (flags must never break the app):
/// - A remote value is authoritative when present, so rollout and kill-switch
///   changes cannot be masked by a stale local override.
/// - Without a remote value, a local override applies, followed by the explicit
///   per-flag default.
/// - Until a payload arrives, the last remote value survives restarts. A flag
///   that has never loaded keeps its safe default.
/// - Request and payload failures preserve the complete cached snapshot. A
///   successfully parsed payload replaces it, so omitted flags return to their
///   local override or default.
///
/// Registry contract (enforced by scripts/lint-feature-flags.py in CI): each
/// flag declares key / owner / reviewBy / defaultWhenUnavailable in the FLAG
/// comment above its property, and its key literal appears nowhere else.
@MainActor
@Observable
final class CmuxFeatureFlags {
    static let shared = CmuxFeatureFlags(publishesOffMainSnapshot: true)

    private static let proUpgradeUIDefault = false

    private static let mobileConnectButtonDefault = false
    private static let sidebarAccountButtonDefault = false

    private static let cloudVMUIDefault = false
    private static let agentChatUIDefault = true
    private nonisolated static let mobileWorkspaceChangesDefault = false
    private static let sidebarWorkspaceAgentSpinnerDefault = false
    private static let simulatorDefault = true
    private static let workspaceTodoControlsDefault = false
    private static let appKitSidebarListDefault = true

    private static let overrideKeyPrefix = "cmux.flags.override."
    private static let remoteCacheKeyPrefix = "cmux.flags.remote."

    // FLAG(key: sidebar-appkit-list-experiment, owner: lawrencecchen,
    //      reviewBy: 2026-10-01, defaultWhenUnavailable: true)
    // Renders the workspace sidebar with the AppKit NSTableView list
    // (virtualized rows, measured-once heights) instead of the SwiftUI
    // LazyVStack. On by default after the remote rollout reached 100%.
    static let appKitSidebarListFlag = CmuxFeatureFlagDefinition(
        key: "sidebar-appkit-list-experiment",
        title: String(
            localized: "featureFlags.appKitSidebarList.title",
            defaultValue: "Lawrence Sidebar"
        ),
        flagDescription: String(
            localized: "featureFlags.appKitSidebarList.description",
            defaultValue: "Renders the workspace sidebar with a native AppKit list and divider for smoother scrolling and resizing with many workspaces."
        ),
        defaultWhenUnavailable: CmuxFeatureFlags.appKitSidebarListDefault
    )

    // FLAG(key: mobile-workspace-changes-enabled-release, owner: lawrencecchen,
    //      reviewBy: 2026-10-01, defaultWhenUnavailable: false)
    // Serves the iOS diff viewer: advertises workspace.changes.v1 to phones
    // and answers the mobile.workspace.changes.* RPCs behind it. Every iOS
    // entry point (workspace-row chip, toolbar button, one-time hint, Changes
    // sheet, summary polling) feature-detects on that capability, so this one
    // Mac-side flag turns the whole feature off end to end. Release builds
    // keep it off until the PostHog flag enables it; DEBUG keeps it on for
    // dogfood.
    nonisolated static let mobileWorkspaceChangesFlag = CmuxFeatureFlagDefinition(
        key: "mobile-workspace-changes-enabled-release",
        title: String(
            localized: "featureFlags.mobileWorkspaceChanges.title",
            defaultValue: "Mobile diff viewer"
        ),
        flagDescription: String(
            localized: "featureFlags.mobileWorkspaceChanges.description",
            defaultValue: "Serves workspace diffs to paired phones: the iOS changes chip, toolbar button, and Changes sheet."
        ),
        defaultWhenUnavailable: CmuxFeatureFlags.mobileWorkspaceChangesDefault
    )

    // Order is load-bearing for the positional typed accessors below. Flags
    // that need a stable public definition are declared independently and
    // included here without repeating their key literal.
    static let allFlags: [CmuxFeatureFlagDefinition] = {
        [
            // FLAG(key: pro-upgrade-ui-enabled-release, owner: lawrencecchen,
            //      reviewBy: 2026-10-01, defaultWhenUnavailable: false)
            // Shows the Pro upgrade entrypoints (sidebar badge, Settings Account
            // card, palette command, Help menu item). Release builds hide them until
            // the PostHog flag is enabled; DEBUG keeps them visible for dogfood.
            CmuxFeatureFlagDefinition(
                key: "pro-upgrade-ui-enabled-release",
                title: String(localized: "featureFlags.proUpgrade.title", defaultValue: "Pro upgrade UI"),
                flagDescription: String(
                    localized: "featureFlags.proUpgrade.description",
                    defaultValue: "Shows Pro upgrade entrypoints in the sidebar, Settings, command palette, and Help menu."
                ),
                defaultWhenUnavailable: CmuxFeatureFlags.proUpgradeUIDefault
            ),

            // FLAG(key: mobile-connect-button-enabled-release, owner: lawrencecchen,
            //      reviewBy: 2026-10-01, defaultWhenUnavailable: false)
            // Shows the bottom-left sidebar iPhone button that opens the Mobile
            // Connect workspace. It stays hidden until the remote flag or a
            // local debug override enables it.
            CmuxFeatureFlagDefinition(
                key: "mobile-connect-button-enabled-release",
                title: String(localized: "featureFlags.mobileConnect.title", defaultValue: "Mobile Connect button"),
                flagDescription: String(
                    localized: "featureFlags.mobileConnect.description",
                    defaultValue: "Shows Mobile Connect entrypoints that open the iPhone pairing workspace."
                ),
                defaultWhenUnavailable: CmuxFeatureFlags.mobileConnectButtonDefault
            ),

            // FLAG(key: sidebar-account-button-enabled-release, owner: lawrencecchen,
            //      reviewBy: 2026-10-01, defaultWhenUnavailable: true)
            // Shows the account control in the bottom-left sidebar footer. The
            // Settings account section remains available when this shortcut is off.
            CmuxFeatureFlagDefinition(
                key: "sidebar-account-button-enabled-release",
                title: String(localized: "featureFlags.sidebarAccount.title", defaultValue: "Sidebar account button"),
                flagDescription: String(
                    localized: "featureFlags.sidebarAccount.description",
                    defaultValue: "Shows the profile and sign-in control in the sidebar footer."
                ),
                defaultWhenUnavailable: CmuxFeatureFlags.sidebarAccountButtonDefault
            ),

            // FLAG(key: cloud-vm-ui-enabled-release, owner: lawrencecchen,
            //      reviewBy: 2026-10-01, defaultWhenUnavailable: false)
            // Shows the Cloud VM entrypoints: the new-workspace dropdown section
            // (Open/Fork/Checkpoint/Restore/Advanced), the caret's direct Cloud
            // VM menu, and the command-palette Cloud VM commands. Release builds
            // hide them until the PostHog flag is enabled; DEBUG keeps them
            // visible for dogfood.
            CmuxFeatureFlagDefinition(
                key: "cloud-vm-ui-enabled-release",
                title: String(localized: "featureFlags.cloudVM.title", defaultValue: "Cloud VM UI"),
                flagDescription: String(
                    localized: "featureFlags.cloudVM.description",
                    defaultValue: "Shows Cloud VM entrypoints in the new-workspace dropdown and command palette."
                ),
                defaultWhenUnavailable: CmuxFeatureFlags.cloudVMUIDefault
            ),

            // FLAG(key: agent-chat-ui-enabled-release, owner: lawrencecchen,
            //      reviewBy: 2026-10-01, defaultWhenUnavailable: false)
            // Shows the Agent Chat entrypoints: the new-workspace dropdown item,
            // command-palette command, surface-tab-bar button, and shared action
            // executor. Hidden by default until the sidecar UX is ready to ship.
            CmuxFeatureFlagDefinition(
                key: "agent-chat-ui-enabled-release",
                title: String(localized: "featureFlags.agentChat.title", defaultValue: "Agent Chat UI"),
                flagDescription: String(
                    localized: "featureFlags.agentChat.description",
                    defaultValue: "Shows Agent Chat entrypoints in the new-workspace dropdown, command palette, and surface tab bar."
                ),
                defaultWhenUnavailable: CmuxFeatureFlags.agentChatUIDefault
            ),

            // FLAG(key: sidebar-workspace-agent-spinner-experiment, owner: lawrencecchen,
            //      reviewBy: 2026-10-01, defaultWhenUnavailable: false)
            // Shows the coding-agent activity spinner in workspace rows. Hidden
            // by default while multi-agent lifecycle edge cases are investigated.
            CmuxFeatureFlagDefinition(
                key: "sidebar-workspace-agent-spinner-experiment",
                title: String(
                    localized: "featureFlags.sidebarWorkspaceAgentSpinner.title",
                    defaultValue: "Workspace agent spinner"
                ),
                flagDescription: String(
                    localized: "featureFlags.sidebarWorkspaceAgentSpinner.description",
                    defaultValue: "Shows a spinner in workspace rows while coding agents are running."
                ),
                defaultWhenUnavailable: CmuxFeatureFlags.sidebarWorkspaceAgentSpinnerDefault
            ),

            // FLAG(key: simulator-enabled-release, owner: lawrencecchen,
            //      reviewBy: 2026-10-01, defaultWhenUnavailable: true)
            // Controls every Simulator entrypoint and active pane. The enabled
            // fallback preserves access when PostHog is unavailable, while the
            // remote value provides a release kill switch.
            CmuxFeatureFlagDefinition(
                key: "simulator-enabled-release",
                title: String(
                    localized: "featureFlags.simulator.title",
                    defaultValue: "Simulator"
                ),
                flagDescription: String(
                    localized: "featureFlags.simulator.description",
                    defaultValue: "Enables iPhone and iPad Simulator panes, commands, and automation."
                ),
                defaultWhenUnavailable: CmuxFeatureFlags.simulatorDefault
            ),

            // FLAG(key: workspace-todo-controls-enabled-release, owner: lawrencecchen,
            //      reviewBy: 2026-10-01, defaultWhenUnavailable: false)
            // Shows user-facing workspace todo controls that create checklist
            // items or set completion/status lanes. Hidden until the local
            // beta setting opts in or the PostHog flag is enabled.
            CmuxFeatureFlagDefinition(
                key: "workspace-todo-controls-enabled-release",
                title: String(
                    localized: "featureFlags.workspaceTodoControls.title",
                    defaultValue: "Workspace todo controls"
                ),
                flagDescription: String(
                    localized: "featureFlags.workspaceTodoControls.description",
                    defaultValue: "Shows Add Checklist Item and workspace completion status controls."
                ),
                defaultWhenUnavailable: CmuxFeatureFlags.workspaceTodoControlsDefault
            ),

            CmuxFeatureFlags.appKitSidebarListFlag,

            CmuxFeatureFlags.mobileWorkspaceChangesFlag,
        ]
    }()

    var isProUpgradeUIEnabled: Bool {
        effectiveValue(for: Self.allFlags[0])
    }

    var isMobileConnectButtonEnabled: Bool {
        effectiveValue(for: Self.allFlags[1])
    }

    var isCloudVMUIEnabled: Bool {
        effectiveValue(for: Self.allFlags[3])
    }

    var isAgentChatUIEnabled: Bool {
        effectiveValue(for: Self.allFlags[4])
    }

    var isSidebarAccountButtonEnabled: Bool {
        effectiveValue(for: Self.allFlags[2])
    }

    var isSidebarWorkspaceAgentSpinnerEnabled: Bool {
        effectiveValue(for: Self.allFlags[5])
    }

    var isSimulatorEnabled: Bool {
        effectiveValue(for: Self.allFlags[6])
    }

    var isWorkspaceTodoControlsEnabled: Bool {
        effectiveValue(for: Self.allFlags[7])
    }

    var isAppKitSidebarListEnabled: Bool {
        effectiveValue(for: Self.appKitSidebarListFlag)
    }

    var isMobileWorkspaceChangesEnabled: Bool {
        effectiveValue(for: Self.mobileWorkspaceChangesFlag)
    }

    /// Effective values mirrored for nonisolated readers: the mobile host
    /// serves status payloads (which carry the capability list) off the main
    /// actor. Written only by the shared instance so test instances cannot
    /// stomp process-wide state. Before the shared instance exists, readers
    /// get the per-flag compile-time default (fail-closed for release flags).
    private nonisolated static let offMainEffectiveValues = OSAllocatedUnfairLock(
        initialState: [String: Bool]()
    )

    nonisolated static func offMainEffectiveValue(
        for definition: CmuxFeatureFlagDefinition
    ) -> Bool {
        offMainEffectiveValues.withLock { $0[definition.key] }
            ?? definition.defaultWhenUnavailable
    }

    @ObservationIgnored
    private let publishesOffMainSnapshot: Bool
    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let remoteFlagValueProvider: (String) -> Any?
    @ObservationIgnored

    private var localOverridesByKey: [String: Bool] = [:]
    private var remoteValuesByKey: [String: Bool] = [:]
    private var resolutionsByKey: [String: CmuxFeatureFlagResolution] = [:]

    init(
        defaults: UserDefaults = .standard,
        remoteFlagValueProvider: @escaping (String) -> Any? = { _ in nil },
        publishesOffMainSnapshot: Bool = false
    ) {
        self.defaults = defaults
        self.publishesOffMainSnapshot = publishesOffMainSnapshot
        self.remoteFlagValueProvider = remoteFlagValueProvider
        localOverridesByKey = Self.allFlags.reduce(into: [:]) { values, definition in
            if let value = Self.storedOverrideValue(for: definition.key, defaults: defaults) {
                values[definition.key] = value
            }
        }
        remoteValuesByKey = Self.allFlags.reduce(into: [:]) { values, definition in
            if let value = Self.storedBoolValue(
                forKey: Self.remoteCacheKey(for: definition.key),
                defaults: defaults
            ) {
                values[definition.key] = value
            }
        }
        recomputeEffectiveValues()
    }

    /// Loads release-control values without initializing analytics. The request
    /// uses a separate anonymous installation identity only when telemetry is
    /// enabled. Opted-out launches use one product-wide ID without targeting
    /// properties, preserving a non-identifying emergency kill switch.
    /// zerocmux: no remote flag refresh; flags are local-only.
    func start() {}










    func effectiveValue(for definition: CmuxFeatureFlagDefinition) -> Bool {
        resolution(for: definition).effectiveValue
    }

    func resolution(for definition: CmuxFeatureFlagDefinition) -> CmuxFeatureFlagResolution {
        resolutionsByKey[definition.key] ?? CmuxFeatureFlagResolution(
            remoteValue: remoteValuesByKey[definition.key],
            overrideValue: localOverridesByKey[definition.key],
            defaultValue: definition.defaultWhenUnavailable
        )
    }

    func overrideValue(for definition: CmuxFeatureFlagDefinition) -> Bool? {
        localOverridesByKey[definition.key]
    }

    func remoteValue(for definition: CmuxFeatureFlagDefinition) -> Bool? {
        remoteValuesByKey[definition.key]
    }

    func setOverride(_ value: Bool?, for definition: CmuxFeatureFlagDefinition) {
        guard value == nil || remoteValuesByKey[definition.key] == nil else { return }

        let previousResolutions = resolutionsByKey
        if let value {
            localOverridesByKey[definition.key] = value
            defaults.set(value, forKey: Self.overrideDefaultsKey(for: definition.key))
        } else {
            localOverridesByKey.removeValue(forKey: definition.key)
            defaults.removeObject(forKey: Self.overrideDefaultsKey(for: definition.key))
        }
        recomputeEffectiveValues()
        postChangeIfNeeded(previousResolutions: previousResolutions)
    }

    func clearAllOverrides() {
        let previousResolutions = resolutionsByKey
        var clearedAnyOverride = false
        for definition in Self.allFlags {
            if localOverridesByKey.removeValue(forKey: definition.key) != nil {
                clearedAnyOverride = true
            }
            defaults.removeObject(forKey: Self.overrideDefaultsKey(for: definition.key))
        }
        guard clearedAnyOverride else { return }
        recomputeEffectiveValues()
        postChangeIfNeeded(previousResolutions: previousResolutions)
    }

    func applyLoadedFlags() {
        let previousResolutions = resolutionsByKey
        for definition in Self.allFlags {
            if let value = Self.coerceBoolFlagValue(remoteFlagValueProvider(definition.key)) {
                remoteValuesByKey[definition.key] = value
                defaults.set(value, forKey: Self.remoteCacheKey(for: definition.key))
            } else if remoteValuesByKey[definition.key] == true {
                remoteValuesByKey.removeValue(forKey: definition.key)
                defaults.removeObject(forKey: Self.remoteCacheKey(for: definition.key))
            }
        }
        recomputeEffectiveValues()
        postChangeIfNeeded(previousResolutions: previousResolutions)
    }

    private func recomputeEffectiveValues() {
        resolutionsByKey = Self.allFlags.reduce(into: [:]) { values, definition in
            values[definition.key] = CmuxFeatureFlagResolution(
                remoteValue: remoteValuesByKey[definition.key],
                overrideValue: localOverridesByKey[definition.key],
                defaultValue: definition.defaultWhenUnavailable
            )
        }
        if publishesOffMainSnapshot {
            let effectiveValues = resolutionsByKey.mapValues(\.effectiveValue)
            Self.offMainEffectiveValues.withLock { $0 = effectiveValues }
        }
    }

    private func postChangeIfNeeded(previousResolutions: [String: CmuxFeatureFlagResolution]) {
        if previousResolutions != resolutionsByKey {
            NotificationCenter.default.post(name: .cmuxFeatureFlagsDidChange, object: self)
        }
    }

    private static func overrideDefaultsKey(for key: String) -> String {
        overrideKeyPrefix + key
    }

    private static func remoteCacheKey(for key: String) -> String {
        remoteCacheKeyPrefix + key
    }

    private static func storedOverrideValue(for key: String, defaults: UserDefaults) -> Bool? {
        storedBoolValue(forKey: overrideDefaultsKey(for: key), defaults: defaults)
    }

    private static func storedBoolValue(forKey key: String, defaults: UserDefaults) -> Bool? {
        guard let value = defaults.object(forKey: key) else {
            return nil
        }
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let numberValue = value as? NSNumber {
            return numberValue.boolValue
        }
        return nil
    }

    nonisolated static func coerceBoolFlagValue(_ value: Any?, default fallback: Bool) -> Bool {
        coerceBoolFlagValue(value) ?? fallback
    }

    nonisolated static func coerceBoolFlagValue(_ value: Any?) -> Bool? {
        guard let value else { return nil }

        if let boolValue = value as? Bool {
            return boolValue
        }

        if let numberValue = value as? NSNumber {
            return numberValue.boolValue
        }

        if let stringValue = value as? String {
            switch stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true":
                return true
            case "false":
                return false
            default:
                return nil
            }
        }

        return nil
    }
}

extension Notification.Name {
    static let cmuxFeatureFlagsDidChange = Notification.Name("cmuxFeatureFlagsDidChange")
}
