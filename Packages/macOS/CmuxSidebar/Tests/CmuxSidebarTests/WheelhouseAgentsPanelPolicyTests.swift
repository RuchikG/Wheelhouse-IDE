import Foundation
import Testing
@testable import CmuxSidebar

@Suite struct WheelhouseAgentsPanelPolicyTests {
    private func agent(_ status: String, children: Int = 0) -> CustomSidebarAgentSnapshot {
        CustomSidebarAgentSnapshot(
            sessionId: UUID().uuidString, kind: "claude", name: "Claude", status: status, stateSince: nil,
            lastActivityAt: Date(timeIntervalSince1970: 0), title: nil, panelId: nil, surfaceId: nil,
            workingDirectory: nil, transcriptPath: nil, pid: nil,
            children: (0..<children).map {
                CustomSidebarAgentChildSnapshot(
                    id: "c\($0)", label: nil, isRunning: $0 == 0, startedAt: Date(timeIntervalSince1970: 0), endedAt: nil)
            }
        )
    }

    @Test func countsLiveAgentsAndTheirSubAgents() {
        #expect(WheelhouseAgentsPanelPolicy.agentCount([]) == 0)
        #expect(WheelhouseAgentsPanelPolicy.agentCount([agent("idle"), agent("ended")]) == 1)
        #expect(WheelhouseAgentsPanelPolicy.agentCount([agent("working"), agent("needs_input")]) == 2)
        #expect(WheelhouseAgentsPanelPolicy.agentCount([agent("working", children: 2)]) == 3)
        #expect(WheelhouseAgentsPanelPolicy.agentCount([agent("ended", children: 2)]) == 0)
    }

    @Test func showsOnlyIntoAClosedSidebar() {
        let action = WheelhouseAgentsPanelPolicy.action
        #expect(action(2, false, false, false) == .show)
        #expect(action(2, false, true, false) == .none)
        #expect(action(2, true, true, false) == .none)
        #expect(action(2, false, false, true) == .none)
    }

    @Test func hidesOnlyItsOwnPanel() {
        let action = WheelhouseAgentsPanelPolicy.action
        #expect(action(1, true, true, false) == .hide)
        #expect(action(1, false, true, false) == .none)
        #expect(action(0, false, false, true) == .none)
    }
}
