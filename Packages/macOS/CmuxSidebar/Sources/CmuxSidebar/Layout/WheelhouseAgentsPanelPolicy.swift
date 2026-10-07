/// When Wheelhouse IDE shows its Agents panel in the right sidebar: while the selected
/// workspace has more than one agent, and never over another right-sidebar mode.
public enum WheelhouseAgentsPanelPolicy {
    public enum Action: Equatable, Sendable {
        case none
        case show
        case hide
    }

    /// Agents that have not ended, plus the sub-agent runs listed under them. Finished runs
    /// stay listed for a while, which keeps the panel from flickering between runs.
    public static func agentCount(_ agents: [CustomSidebarAgentSnapshot]) -> Int {
        agents.filter { $0.status != "ended" }.reduce(0) { $0 + 1 + $1.children.count }
    }

    /// - Parameters:
    ///   - panelShowing: the right sidebar is open on the Agents panel.
    ///   - sidebarVisible: the right sidebar is open on anything.
    ///   - dismissed: the user closed the panel for this workspace.
    public static func action(agentCount: Int, panelShowing: Bool, sidebarVisible: Bool, dismissed: Bool) -> Action {
        if agentCount < 2 { return panelShowing ? .hide : .none }
        return sidebarVisible || dismissed ? .none : .show
    }
}
