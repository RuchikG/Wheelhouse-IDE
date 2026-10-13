import CmuxSwiftRender
import Foundation
import Testing
@testable import CmuxSidebar

@Suite struct WheelhouseProjectAgentTests {
    private let kit = WheelhouseHarness(
        id: "kit", name: "Kit", launcher: ["kit"], wraps: "claude", start: "kit claude -m fast {prompt}")
    private let silent = WheelhouseHarness(id: "silent", name: "Silent", process: ["silent"])
    private var harnesses: [WheelhouseHarness] { [silent, kit] + WheelhouseHarness.builtIn }

    @Test func theFirstMessageIsOneQuotedArgument() {
        #expect(WheelhouseHarness.builtIn[0].startCommand(prompt: "Read ~/a b.md, it's short")
            == "claude 'Read ~/a b.md, it'\\''s short'")
        #expect(kit.startCommand(prompt: "go") == "kit claude -m fast 'go'")
        #expect(silent.startCommand(prompt: "go") == nil)
    }

    @Test func aListedHarnessCanNameItsStartCommand() throws {
        let list = Data(#"[{"id": "codex", "name": "Codex", "process": ["codex"], "start": "codex -m big {prompt}"}]"#.utf8)
        let codex = try #require(WheelhouseHarness.all(userList: list).first { $0.id == "codex" })
        #expect(codex.startCommand(prompt: "hi") == "codex -m big 'hi'")
    }

    @Test func theProjectsHarnessWinsThenTheOneForEveryProjectThenTheFirstThatStarts() {
        let pick = { (project: String?, every: String?) in
            WheelhouseHarness.toStart(project: project, everyProject: every, from: self.harnesses)?.id
        }
        #expect(pick("codex", "kit") == "codex")
        #expect(pick(nil, "codex") == "codex")
        #expect(pick("silent", "codex") == "codex")
        #expect(pick("gone", nil) == "kit")
        #expect(WheelhouseHarness.toStart(project: nil, everyProject: nil, from: [silent]) == nil)
    }

    @Test func aSessionKeepsItsRoleAndTranscriptAcrossAResume() {
        var history = WheelhouseSessionHistory()
        let plain = WheelhouseSessionObservation(id: "a", kind: "codex", name: "Codex", sessionId: "a")
        var own = plain
        own.role = WheelhouseProjectAgent.role
        own.transcript = "/t/a.jsonl"
        _ = history.observe([plain], now: 100)
        #expect(history.projectAgent.running == nil)
        do { let changed = history.observe([own], now: 103); #expect(changed) }
        #expect(history.projectAgent.running?.id == "a")
        _ = history.observe([], now: 106)
        #expect(history.projectAgent.running == nil)
        #expect(history.projectAgent.last?.transcript == "/t/a.jsonl")
        // Resumed from the history: the app no longer knows which tab it started.
        _ = history.observe([plain], now: 200)
        #expect(history.projectAgent.running?.role == "project")
        let saved = WheelhouseSessionHistory(data: history.encoded())
        #expect(saved.projectAgent.running?.transcript == "/t/a.jsonl")
    }

    @Test func theLatestEndedSessionOfTheProjectAgentIsItsLast() {
        let record = { (id: String, ended: Double?, role: String?) in
            WheelhouseSessionRecord(
                id: id, kind: "codex", name: "Codex", startedAt: 1, lastSeenAt: 1, endedAt: ended, role: role)
        }
        let history = WheelhouseSessionHistory(records: [
            record("a", 50, "project"), record("b", 90, nil), record("c", 70, "project"), record("d", nil, nil),
        ])
        #expect(history.projectAgent.last?.id == "c")
        #expect(history.projectAgent.running == nil)
    }

    @Test func aSidebarIsToldWhatItNeedsToStartAndFindTheAgent() throws {
        let panel = UUID()
        let running = WheelhouseSessionRecord(
            id: "s1", kind: "kit", name: "Kit", title: "Where are we?", startedAt: 10, lastSeenAt: 20, resume: "kit r s1",
            role: "project")
        let agent = WheelhouseProjectAgent(
            harness: kit, harnesses: [kit] + WheelhouseHarness.builtIn, hasOwnHarness: true, running: running,
            runningPanel: panel, memoryPath: "/home/memory/refunds.md", memoryWrittenAt: 99)
        guard case .object(let fields) = agent.value(project: "refunds") else {
            Issue.record("not an object")
            return
        }
        #expect(fields["harness"] == .object(["id": .string("kit"), "name": .string("Kit")]))
        #expect(fields["canStart"] == .bool(true))
        #expect(fields["memoryEpoch"] == .int(99))
        guard case .array(let choices) = fields["harnesses"], case .object(let session) = fields["running"] else {
            Issue.record("no choices or no running session")
            return
        }
        #expect(choices.count == 3)
        #expect(session["panelId"] == .string(panel.uuidString))
        #expect(session["project"] == .string("refunds"))
        #expect(session["canResume"] == .bool(true))

        var remote = agent
        remote.unavailable = "Not on SSH hosts yet"
        guard case .object(let other) = remote.value(project: "refunds") else { return }
        #expect(other["canStart"] == .bool(false))
    }

    @Test func aTopLevelKeyIsReadFromAProjectFileOrTheSettings() {
        let text = "name: \"Refunds: phase 2\"\nlinks:\n  - harness: no\nharness: codex  # mine\n"
        #expect(WheelhouseProjectFile.name(in: text) == "Refunds: phase 2")
        #expect(WheelhouseProjectFile.value(of: "harness", in: text) == "codex")
        #expect(WheelhouseProjectFile.value(of: "harness", in: "name: A\n") == nil)
    }

    @Test func theFirstMessagesNameTheBriefAndWhoTheAgentIs() {
        #expect(WheelhouseProjectAgent.Prompt.projectAgent(name: "Refunds", brief: "/h/briefs/refunds.md")
            == "Project agent for Refunds: read /h/briefs/refunds.md and follow its section for the project agent.")
        #expect(WheelhouseProjectAgent.Prompt.agent(name: "Refunds", brief: "/h/briefs/refunds.md")
            == "New agent for Refunds: read /h/briefs/refunds.md and follow its section for a new agent.")
        #expect(WheelhouseProjectAgent.Prompt.update(brief: "/h/briefs/refunds.md").contains("/h/briefs/refunds.md"))
    }
}
