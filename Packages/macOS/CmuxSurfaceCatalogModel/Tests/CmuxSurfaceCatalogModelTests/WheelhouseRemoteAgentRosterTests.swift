import Foundation
import Testing
@testable import CmuxSurfaceCatalogModel

@Suite struct WheelhouseRemoteAgentRosterTests {
    private let workspace = UUID()
    private let panel = UUID()
    private let start = Date(timeIntervalSince1970: 1_000)

    private func status(_ state: String, agent: String = "claude") -> RemoteAgentSidebarStatus {
        RemoteAgentSidebarStatus(badge: SurfaceAgentBadge(state: state, source: "hook", agent: agent))!
    }

    @Test func rowsUseTheNamesOfLocalSessions() {
        var roster = WheelhouseRemoteAgentRoster()
        let codexPanel = UUID()
        roster.update([workspace: [panel: status("blocked"), codexPanel: status("working", agent: "codex")]], now: start)
        let rows = Dictionary(uniqueKeysWithValues: roster.rows(workspaceID: workspace).map { ($0.panelID, $0) })
        #expect(rows[panel]?.kind == "claude")
        #expect(rows[panel]?.status == "needs_input")
        #expect(rows[codexPanel]?.kind == "codex")
        #expect(rows[codexPanel]?.status == "working")
    }

    @Test func sinceRestartsOnlyWhenTheStatusChanges() {
        var roster = WheelhouseRemoteAgentRoster()
        roster.update([workspace: [panel: status("working")]], now: start)
        roster.update([workspace: [panel: status("working")]], now: start.addingTimeInterval(30))
        #expect(roster.rows(workspaceID: workspace).first?.since == start)
        roster.update([workspace: [panel: status("idle")]], now: start.addingTimeInterval(60))
        #expect(roster.rows(workspaceID: workspace).first?.status == "idle")
        #expect(roster.rows(workspaceID: workspace).first?.since == start.addingTimeInterval(60))
    }

    @Test func aTerminalWithoutAnAgentLeavesTheRoster() {
        var roster = WheelhouseRemoteAgentRoster()
        roster.update([workspace: [panel: status("working")]], now: start)
        roster.update([:], now: start.addingTimeInterval(5))
        #expect(roster.rows(workspaceID: workspace).isEmpty)
    }
}
