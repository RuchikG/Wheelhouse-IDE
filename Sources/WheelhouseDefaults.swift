import Foundation

/// Wheelhouse IDE's preferences on top of cmux's defaults. A registered value
/// applies until the user changes the setting, so each can still be switched
/// back in Settings or the debug menu.
enum WheelhouseDefaults {
    /// Whether attaching to an SSH host installs cmux's agent hooks in that
    /// host's Claude Code and Codex settings. Off until the user turns it on.
    static let remoteAgentHooksKey = "wheelhouse.remoteAgentHooks.enabled"

    static var installsRemoteAgentHooks: Bool {
        UserDefaults.standard.bool(forKey: remoteAgentHooksKey)
    }

    /// Whether this app runs cmux's Computer Use helper and hands its tools to
    /// agents. Off until the user turns it on.
    static let computerUseKey = "wheelhouse.computerUse.enabled"

    static var allowsComputerUse: Bool {
        UserDefaults.standard.bool(forKey: computerUseKey)
    }

    static func register(in defaults: UserDefaults = .standard) {
        // The agent wrappers started in this app's terminals read this.
        if !allowsComputerUse { setenv("CMUX_COMPUTER_USE_MCP_DISABLED", "1", 1) }
        var values: [String: Any] = [
            // No analytics, crash reports or feature-flag requests go to cmux's
            // services; flags then use their built-in defaults and the overrides below.
            "sendAnonymousTelemetry": false,
            // The "dev build" label under the sidebar.
            "showSidebarDevBuildBanner": false,
        ]
        // cmux Pro upgrade prompts, the cmux account control and the phone pairing
        // button: Manaflow services this fork does not use. These are local overrides
        // of release flags, which stay evaluated where cmux evaluates them.
        for flag in ["pro-upgrade-ui", "sidebar-account-button", "mobile-connect-button"] {
            values["cmux.flags.override.\(flag)-enabled-release"] = false
        }
        defaults.register(defaults: values)
    }
}
