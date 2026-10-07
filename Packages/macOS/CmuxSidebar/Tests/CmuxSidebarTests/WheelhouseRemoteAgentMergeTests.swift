import Foundation
import Testing
@testable import CmuxSidebar

@Suite struct WheelhouseRemoteAgentMergeTests {
    private let panel = UUID()
    private let surface = UUID()
    private let start = Date(timeIntervalSince1970: 1_000)

    private func local(_ status: String, panelId: UUID?, title: String? = nil) -> CustomSidebarAgentSnapshot {
        CustomSidebarAgentSnapshot(
            sessionId: "s-\(status)", kind: "claude", name: "Claude", status: status, stateSince: nil,
            lastActivityAt: Date(timeIntervalSince1970: 900), title: title, panelId: panelId, surfaceId: surface,
            workingDirectory: nil, transcriptPath: nil, pid: nil)
    }

    private func remote(_ status: String) -> WheelhouseRemoteAgentState {
        WheelhouseRemoteAgentState(panelId: panel, kind: "claude", name: "Claude", status: status, since: start)
    }

    @Test func aTerminalWithoutASessionGetsAnEntry() {
        let merged = WheelhouseRemoteAgentMerge.merge([], remote: [remote("working")], surfaceIdByPanelId: [panel: surface])
        #expect(merged.count == 1)
        #expect(merged.first?.status == "working")
        #expect(merged.first?.stateSince == start)
        #expect(merged.first?.surfaceId == surface)
        #expect(merged.first?.sessionId == "remote:\(panel.uuidString):claude")
    }

    @Test func aListedSessionTakesTheHostsState() {
        let merged = WheelhouseRemoteAgentMerge.merge(
            [local("idle", panelId: panel, title: "Run the suite"), local("ended", panelId: panel)],
            remote: [remote("needs_input")], surfaceIdByPanelId: [panel: surface])
        #expect(merged.map(\.status) == ["needs_input", "ended"])
        #expect(merged.first?.sessionId == "s-idle")
        #expect(merged.first?.title == "Run the suite")
    }

    @Test func aClosedTerminalAndOtherSessionsAreLeftAlone() {
        let other = local("working", panelId: UUID())
        #expect(WheelhouseRemoteAgentMerge.merge([other], remote: [remote("working")], surfaceIdByPanelId: [:]) == [other])
        #expect(WheelhouseRemoteAgentMerge.merge([other], remote: [], surfaceIdByPanelId: [panel: surface]) == [other])
    }

    @Test func idleHasNoSince() {
        let merged = WheelhouseRemoteAgentMerge.merge([], remote: [remote("idle")], surfaceIdByPanelId: [panel: surface])
        #expect(merged.first?.stateSince == nil)
        #expect(merged.first?.lastActivityAt == start)
    }
}

@Suite struct WheelhouseAgentListCleanupTests {
    private let launch = Date(timeIntervalSince1970: 4)

    private func agent(_ id: String, _ status: String, panel: UUID?, pid: Int?, at time: TimeInterval) -> CustomSidebarAgentSnapshot {
        CustomSidebarAgentSnapshot(
            sessionId: id, kind: "claude", name: "Claude", status: status, stateSince: nil,
            lastActivityAt: Date(timeIntervalSince1970: time), title: nil, panelId: panel, surfaceId: nil,
            workingDirectory: nil, transcriptPath: nil, pid: pid)
    }

    @Test func aSessionWhoseProcessIsGoneIsDropped() {
        let panel = UUID()
        let cleaned = WheelhouseAgentListCleanup.removingStale(
            [agent("dead", "idle", panel: panel, pid: 7, at: 10), agent("other", "working", panel: UUID(), pid: 8, at: 5)],
            restoredBefore: launch, isProcessAlive: { $0 == 8 })
        #expect(cleaned.map(\.sessionId) == ["other"])
    }

    @Test func aTerminalKeepsItsNewestSession() {
        let panel = UUID()
        let cleaned = WheelhouseAgentListCleanup.removingStale(
            [
                agent("restored", "idle", panel: panel, pid: nil, at: 30),
                agent("running", "needs_input", panel: panel, pid: 9, at: 20),
                agent("older", "idle", panel: panel, pid: nil, at: 10),
                agent("ended", "ended", panel: panel, pid: nil, at: 40),
            ],
            restoredBefore: launch, isProcessAlive: { _ in true })
        #expect(cleaned.map(\.sessionId) == ["running", "ended"])
    }

    @Test func aRestoredSessionStaysOutUntilItIsHeardFrom() {
        let restored = agent("restored", "idle", panel: UUID(), pid: nil, at: 3)
        let heard = agent("heard", "idle", panel: UUID(), pid: nil, at: 30)
        let unbound = agent("unbound", "working", panel: nil, pid: nil, at: 40)
        let cleaned = WheelhouseAgentListCleanup.removingStale(
            [restored, heard, unbound], restoredBefore: launch, isProcessAlive: { _ in false })
        #expect(cleaned == [heard, unbound])
    }
}

