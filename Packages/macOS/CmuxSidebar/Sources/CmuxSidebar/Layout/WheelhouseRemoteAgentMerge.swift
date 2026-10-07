public import Foundation

/// The state of the agent in one `cmux ssh` terminal, as its host reports it.
public struct WheelhouseRemoteAgentState: Sendable, Equatable {
    public let panelId: UUID
    public let kind: String
    public let name: String
    /// "working" | "needs_input" | "idle".
    public let status: String
    public let since: Date

    public init(panelId: UUID, kind: String, name: String, status: String, since: Date) {
        self.panelId = panelId
        self.kind = kind
        self.name = name
        self.status = status
        self.since = since
    }
}

/// Puts the agents on SSH hosts into a workspace's `agents`. A session the app already lists
/// for the same terminal takes the host's state; a terminal without one gets an entry.
public enum WheelhouseRemoteAgentMerge {
    public static func merge(
        _ agents: [CustomSidebarAgentSnapshot],
        remote: [WheelhouseRemoteAgentState],
        surfaceIdByPanelId: [UUID: UUID]
    ) -> [CustomSidebarAgentSnapshot] {
        var pending: [UUID: WheelhouseRemoteAgentState] = [:]
        for state in remote where surfaceIdByPanelId[state.panelId] != nil {
            pending[state.panelId] = state
        }
        guard !pending.isEmpty else { return agents }
        var merged = agents.map { agent -> CustomSidebarAgentSnapshot in
            guard agent.status != "ended", let panelId = agent.panelId,
                  let state = pending.removeValue(forKey: panelId) else { return agent }
            return snapshot(state, surfaceId: agent.surfaceId, basedOn: agent)
        }
        for state in remote {
            guard let state = pending.removeValue(forKey: state.panelId) else { continue }
            merged.append(snapshot(state, surfaceId: surfaceIdByPanelId[state.panelId], basedOn: nil))
        }
        return merged
    }

    private static func snapshot(
        _ state: WheelhouseRemoteAgentState, surfaceId: UUID?, basedOn agent: CustomSidebarAgentSnapshot?
    ) -> CustomSidebarAgentSnapshot {
        CustomSidebarAgentSnapshot(
            sessionId: agent?.sessionId ?? "remote:\(state.panelId.uuidString):\(state.kind)",
            kind: agent?.kind ?? state.kind,
            name: agent?.name ?? state.name,
            status: state.status,
            stateSince: state.status == "idle" ? nil : state.since,
            lastActivityAt: max(agent?.lastActivityAt ?? state.since, state.since),
            title: agent?.title,
            panelId: state.panelId,
            surfaceId: surfaceId,
            workingDirectory: agent?.workingDirectory,
            transcriptPath: agent?.transcriptPath,
            pid: agent?.pid,
            children: agent?.children ?? []
        )
    }
}

/// Drops sessions that can no longer be running from a workspace's `agents`: a session whose
/// process is gone, a session without a process that has not been heard from since the app
/// restored it at launch, and an older session of a terminal that hosts a newer one. The app
/// lists all of these as idle.
public enum WheelhouseAgentListCleanup {
    /// - Parameter restoredBefore: when the app had finished restoring sessions at launch.
    public static func removingStale(
        _ agents: [CustomSidebarAgentSnapshot], restoredBefore: Date, isProcessAlive: (Int) -> Bool
    ) -> [CustomSidebarAgentSnapshot] {
        func isRunning(_ agent: CustomSidebarAgentSnapshot) -> Bool {
            guard let pid = agent.pid else { return agent.lastActivityAt > restoredBefore }
            return isProcessAlive(pid)
        }
        var newestByPanel: [UUID: CustomSidebarAgentSnapshot] = [:]
        let live = agents.filter { $0.status != "ended" && isRunning($0) }
        for agent in live {
            guard let panelId = agent.panelId else { continue }
            if let current = newestByPanel[panelId], !isNewer(agent, than: current) { continue }
            newestByPanel[panelId] = agent
        }
        return agents.filter { agent in
            guard agent.status != "ended" else { return true }
            guard isRunning(agent) else { return false }
            guard let panelId = agent.panelId else { return true }
            return newestByPanel[panelId]?.sessionId == agent.sessionId
        }
    }

    /// A session with a process outranks one without; then the later activity wins.
    private static func isNewer(_ agent: CustomSidebarAgentSnapshot, than other: CustomSidebarAgentSnapshot) -> Bool {
        if (agent.pid != nil) != (other.pid != nil) { return agent.pid != nil }
        return agent.lastActivityAt > other.lastActivityAt
    }
}
