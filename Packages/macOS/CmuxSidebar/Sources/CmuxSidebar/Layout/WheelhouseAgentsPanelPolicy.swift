/// When Wheelhouse IDE shows its Agents panel in the right sidebar: for every project, so
/// that the project's earlier sessions are at hand, and never over another right-sidebar mode.
public enum WheelhouseAgentsPanelPolicy {
    public enum Action: Equatable, Sendable {
        case none
        case show
        case hide
    }

    /// - Parameters:
    ///   - isProject: the selected workspace is a project's.
    ///   - panelShowing: the right sidebar is open on the Agents panel.
    ///   - sidebarVisible: the right sidebar is open on anything.
    ///   - collapsed: the user collapsed the panel to its button and has not opened it again.
    public static func action(isProject: Bool, panelShowing: Bool, sidebarVisible: Bool, collapsed: Bool) -> Action {
        guard isProject else { return panelShowing ? .hide : .none }
        return sidebarVisible || collapsed ? .none : .show
    }
}
