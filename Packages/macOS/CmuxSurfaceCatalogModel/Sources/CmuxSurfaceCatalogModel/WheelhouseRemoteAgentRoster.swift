public import Foundation

/// The agents on `cmux ssh` terminals as rows for custom sidebars, which read
/// `workspaces[i].agents` and not the workspace status that `RemoteAgentSidebarStatus` feeds.
public struct WheelhouseRemoteAgentRoster: Sendable {
    public struct Row: Hashable, Sendable {
        public let panelID: UUID
        /// The agent's source name as local sessions report it, e.g. "claude".
        public let kind: String
        /// "working" | "needs_input" | "idle", the wire names of local sessions.
        public let status: String
        /// When the terminal's agent entered this status.
        public let since: Date
    }

    private var rowsByWorkspace: [UUID: [UUID: Row]] = [:]

    public init() {}

    /// Replaces the roster with the current status of every remote terminal, per workspace and
    /// panel. A row keeps its `since` while its agent and status stay the same.
    public mutating func update(_ statuses: [UUID: [UUID: RemoteAgentSidebarStatus]], now: Date) {
        var next: [UUID: [UUID: Row]] = [:]
        for (workspaceID, panels) in statuses {
            for (panelID, status) in panels {
                let kind = Self.kind(statusKey: status.statusKey)
                let wire = Self.wireStatus(status.activity)
                if let current = rowsByWorkspace[workspaceID]?[panelID], current.kind == kind, current.status == wire {
                    next[workspaceID, default: [:]][panelID] = current
                } else {
                    next[workspaceID, default: [:]][panelID] = Row(panelID: panelID, kind: kind, status: wire, since: now)
                }
            }
        }
        rowsByWorkspace = next
    }

    /// The workspace's rows in a stable order.
    public func rows(workspaceID: UUID) -> [Row] {
        (rowsByWorkspace[workspaceID] ?? [:]).values.sorted { $0.panelID.uuidString < $1.panelID.uuidString }
    }

    static func kind(statusKey: String) -> String {
        let key = String(statusKey.dropFirst(RemoteAgentSidebarStatus.statusKeyPrefix.count))
        return key == "claude_code" ? "claude" : key
    }

    static func wireStatus(_ activity: RemoteAgentSidebarStatus.Activity) -> String {
        switch activity {
        case .running: "working"
        case .needsInput: "needs_input"
        case .idle: "idle"
        }
    }
}
