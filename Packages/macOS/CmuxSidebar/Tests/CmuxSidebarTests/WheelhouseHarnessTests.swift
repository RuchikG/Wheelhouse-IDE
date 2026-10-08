import Foundation
import Testing
@testable import CmuxSidebar

@Suite struct WheelhouseHarnessTests {
    private let launcher = WheelhouseHarness(
        id: "kit", name: "Kit", launcher: ["kit"], wraps: "claude", resume: "kit claude --resume {id}")
    private var harnesses: [WheelhouseHarness] { [launcher] + WheelhouseHarness.builtIn }

    @Test func findsTheAgentsOfATerminal() {
        let processes = [
            WheelhouseProcess(pid: 10, parent: 1, name: "zsh"),
            WheelhouseProcess(pid: 11, parent: 10, name: "claude"),
            WheelhouseProcess(pid: 12, parent: 11, name: "node"),
            WheelhouseProcess(pid: 13, parent: 11, name: "claude"),
            WheelhouseProcess(pid: 20, parent: 10, name: "vim"),
        ]
        let agents = WheelhouseHarnessMatch.agents(in: processes, harnesses: harnesses)
        #expect(agents.map(\.process.pid) == [11])
        #expect(agents.map(\.harness.id) == ["claude"])
    }

    @Test func anAgentStartedByALauncherCountsAsTheLaunchers() {
        let processes = [
            WheelhouseProcess(pid: 10, parent: 1, name: "zsh"),
            WheelhouseProcess(pid: 11, parent: 10, name: "node", arguments: ["node", "/opt/bin/kit", "claude"]),
            WheelhouseProcess(pid: 12, parent: 11, name: "claude"),
            WheelhouseProcess(pid: 30, parent: 1, name: "codex"),
        ]
        let agents = WheelhouseHarnessMatch.agents(in: processes, harnesses: harnesses)
        #expect(agents.map(\.process.pid) == [12, 30])
        #expect(agents.map(\.program.id) == ["claude", "codex"])
        #expect(agents.map(\.harness.id) == ["kit", "codex"])
    }

    @Test func aListedHarnessReplacesTheBuiltInOfItsId() throws {
        let list = Data("""
        [{"id": "codex", "name": "My Codex", "process": ["codex", "cdx"], "resume": "cdx resume {id}"},
         {"id": "kit", "name": "Kit", "launcher": ["kit"], "wraps": "claude"},
         {"id": "", "name": "Nameless"}]
        """.utf8)
        let all = WheelhouseHarness.all(userList: list)
        #expect(all.map(\.id) == ["codex", "kit", "claude"])
        #expect(all[0].name == "My Codex")
        #expect(WheelhouseHarness.all(userList: nil) == WheelhouseHarness.builtIn)
        #expect(WheelhouseHarness.all(userList: Data("{".utf8)) == WheelhouseHarness.builtIn)
    }

    @Test func buildsTheCommandThatOpensASessionAgain() {
        #expect(WheelhouseHarness.builtIn[0].resumeCommand(id: "7f3a-2c") == "claude --resume 7f3a-2c")
        #expect(launcher.resumeCommand(id: "7f3a") == "kit claude --resume 7f3a")
        #expect(launcher.resumeCommand(id: "x; rm -rf ~") == nil)
        #expect(WheelhouseHarness(id: "a", name: "A").resumeCommand(id: "7f3a") == nil)
    }

    @Test func knowsAnAgentByTheNameItWasCalledBy() {
        let processes = [WheelhouseProcess(pid: 11, parent: 1, name: "2.1.293", arguments: ["claude", "--resume"])]
        #expect(WheelhouseHarnessMatch.agents(in: processes, harnesses: harnesses).map(\.harness.id) == ["claude"])
    }

    @Test func findsASessionsTranscript() {
        let claude = WheelhouseHarness.builtIn[0]
        #expect(claude.transcriptPath(id: "7f3a", directory: "/Users/me/work.d/app")
            == "~/.claude/projects/-Users-me-work-d-app/7f3a.jsonl")
        #expect(WheelhouseHarness.builtIn[1].transcriptPath(id: "7f3a", directory: "/work") == nil)
    }

    @Test func readsTheSessionIdASessionFileIsNamedWith() {
        let name = "rollout-2026-10-07T16-43-54-01a118c0-797a-7a51-b063-7fa3a9337e65.jsonl"
        #expect(WheelhouseHarness.sessionId(inFileName: name) == "01a118c0-797a-7a51-b063-7fa3a9337e65")
        #expect(WheelhouseHarness.sessionId(inFileName: "session-abc123.json") == "abc123")
        #expect(WheelhouseHarness.sessionId(inFileName: "notes.jsonl") == nil)
    }

    @Test func readsTheFirstPromptOfATranscript() {
        let claude = """
        {"type":"summary","summary":"x"}
        {"type":"user","isMeta":true,"message":{"role":"user","content":"<local-command-caveat>…"}}
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":"Build the refund\\nform"}]}}
        {"type":"user","message":{"role":"user","content":"later"}}
        """
        #expect(WheelhouseTranscript.firstPrompt(inLines: claude.split(separator: "\n")) == "Build the refund form")
        let codex = """
        {"type":"session_meta","payload":{"id":"a","cwd":"/work"}}
        not json
        {"type":"event_msg","payload":{"type":"user_message","message":"Review the design"}}
        """
        #expect(WheelhouseTranscript.firstPrompt(inLines: codex.split(separator: "\n")) == "Review the design")
        #expect(WheelhouseTranscript.firstPrompt(inLines: ["{}"]) == nil)
        let threads = """
        {"type":"session_meta","payload":{"instructions":[{"role":"user","content":"not the prompt"}]}}
        {"type":"history_mutation","payload":{"items":[{"type":"message","role":"developer","content":[{"type":"input_text","text":"rules"}]},{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>x</environment_context>"}]}]}}
        {"type":"history_mutation","payload":{"items":[{"type":"message","role":"user","content":[{"type":"input_text","text":"Run the suite"}]}]}}
        """
        #expect(WheelhouseTranscript.firstPrompt(inLines: threads.split(separator: "\n")) == "Run the suite")
    }

    @Test func tellsWhichFolderASessionFileBelongsTo() {
        let head = #"{"type":"session_meta","payload":{"id":"a","cwd":"/work/app","instructions":"very long"#
        #expect(WheelhouseTranscript.sessionFileHead(head, isIn: "/work/app"))
        #expect(!WheelhouseTranscript.sessionFileHead(head, isIn: "/work"))
        #expect(WheelhouseTranscript.sessionFileHead(#"{"cwd": "\/work\/app"}"#, isIn: "/work/app"))
        #expect(!WheelhouseTranscript.sessionFileHead("{\"id\":1}\n{\"cwd\":\"/work/app\"}", isIn: "/work/app"))
    }
}
