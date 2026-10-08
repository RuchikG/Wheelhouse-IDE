import Testing
@testable import CmuxSidebar

@Suite struct WheelhouseAgentsPanelPolicyTests {
    private let action = WheelhouseAgentsPanelPolicy.action

    @Test func showsForAProjectIntoAClosedSidebar() {
        #expect(action(true, false, false, false) == .show)
        #expect(action(true, false, true, false) == .none)
        #expect(action(true, true, true, false) == .none)
    }

    @Test func staysCollapsedUntilTheUserOpensIt() {
        #expect(action(true, false, false, true) == .none)
    }

    @Test func hidesOnlyItsOwnPanelOutsideAProject() {
        #expect(action(false, true, true, false) == .hide)
        #expect(action(false, false, true, false) == .none)
        #expect(action(false, false, false, true) == .none)
    }
}
