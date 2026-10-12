import Foundation
import Testing
@testable import CmuxSidebar

/// Runs the host probe on this machine against a made-up `/proc`: the same program a host
/// runs, reading a folder the test fills.
@Suite struct WheelhouseRemoteSessionsTests {
    private let launcher = WheelhouseHarness(
        id: "kit", name: "Kit", launcher: ["kit"], wraps: "claude", resume: "kit claude --resume {id}")
    private var harnesses: [WheelhouseHarness] { [launcher] + WheelhouseHarness.builtIn }

    /// A host's home folder and `/proc`, under one temporary folder.
    private final class Host {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }
        var proc: URL { root.appendingPathComponent("proc") }

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("remote-sessions-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: proc, withIntermediateDirectories: true)
            // Booted at 1,000,000; the tests' processes start a number of clock ticks later.
            try Data("cpu 1 2 3\nbtime 1000000\n".utf8).write(to: proc.appendingPathComponent("stat"))
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func write(_ text: String, to path: String) throws {
            let url = home.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }

        /// - Parameter terminal: nil for a process that is not in a cmux terminal.
        func process(
            _ pid: Int, parent: Int, command: String, exe: String, arguments: [String],
            directory: String, terminal: String?, startTicks: Int = 0
        ) throws {
            let folder = proc.appendingPathComponent(String(pid), isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var environment = ["HOME=/home/someone", "SECRET_TOKEN=do-not-read"]
            if let terminal { environment.append("\(WheelhouseRemoteSessionProbe.terminalVariable)=\(terminal)") }
            try Data((environment.joined(separator: "\0") + "\0").utf8).write(to: folder.appendingPathComponent("environ"))
            let rest = ["S", String(parent)] + Array(repeating: "0", count: 17) + [String(startTicks), "0"]
            try Data("\(pid) (\(command)) \(rest.joined(separator: " "))\n".utf8)
                .write(to: folder.appendingPathComponent("stat"))
            try Data((arguments.joined(separator: "\0") + "\0").utf8).write(to: folder.appendingPathComponent("cmdline"))
            try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("exe").path, withDestinationPath: exe)
            try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("cwd").path, withDestinationPath: directory)
        }
    }

    private func probe(_ host: Host, harnesses: [WheelhouseHarness]) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = WheelhouseRemoteSessionProbe.arguments(harnesses: harnesses) + [host.proc.path]
        process.environment = ["HOME": host.home.path, "PATH": "/usr/bin:/bin"]
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return data
    }

    @Test func findsAnAgentsSessionInItsTerminal() throws {
        let host = try Host()
        try host.process(10, parent: 1, command: "bash", exe: "/usr/bin/bash", arguments: ["-bash"], directory: "/srv/app", terminal: "term_a")
        // Installed under a version number, as Claude Code is on Linux.
        try host.process(
            11, parent: 10, command: "claude", exe: "/opt/claude/versions/2.1.0",
            arguments: ["claude", "--api-key", "sk-secret"], directory: "/srv/app", terminal: "term_a")
        try host.process(12, parent: 11, command: "node", exe: "/usr/bin/node", arguments: ["node", "helper.js"], directory: "/srv/app", terminal: "term_a")
        try host.process(20, parent: 1, command: "claude", exe: "/opt/claude/versions/2.1.0", arguments: ["claude"], directory: "/srv/app", terminal: nil)
        try host.write(#"{"pid": 11, "sessionId": "0a1b2c3d-1111-2222-3333-444455556666"}"#, to: ".claude/sessions/11.json")
        try host.write(#"{"pid": 20, "sessionId": "ffffffff-1111-2222-3333-444455556666"}"#, to: ".claude/sessions/20.json")
        try host.write(
            """
            {"type":"summary","isMeta":true,"message":{"role":"user","content":"<system>ignore</system>"}}
            {"type":"user","message":{"role":"user","content":[{"type":"text","text":"Fix the   cart\\ntotals"}]}}

            """,
            to: ".claude/projects/-srv-app/0a1b2c3d-1111-2222-3333-444455556666.jsonl")

        let output = try probe(host, harnesses: harnesses)
        #expect(!String(decoding: output, as: UTF8.self).contains("sk-secret"))
        #expect(!String(decoding: output, as: UTF8.self).contains("do-not-read"))
        let sessions = try #require(WheelhouseRemoteSessionProbe.sessions(inOutput: output, harnesses: harnesses))
        #expect(sessions == [
            WheelhouseRemoteSession(
                id: "0a1b2c3d-1111-2222-3333-444455556666", harness: WheelhouseHarness.builtIn[0], terminal: "term_a",
                directory: "/srv/app", title: "Fix the cart totals"),
        ])
    }

    @Test func anAgentStartedByALauncherCountsAsTheLaunchers() throws {
        let host = try Host()
        try host.process(10, parent: 1, command: "bash", exe: "/usr/bin/bash", arguments: ["-bash"], directory: "/work", terminal: "term_b")
        try host.process(11, parent: 10, command: "node", exe: "/usr/bin/node", arguments: ["node", "/opt/bin/kit", "claude"], directory: "/work", terminal: "term_b")
        try host.process(12, parent: 11, command: "claude", exe: "/opt/claude/claude", arguments: ["claude"], directory: "/work", terminal: "term_b")
        try host.write(#"{"sessionId": "abc-123"}"#, to: ".claude/sessions/12.json")

        let sessions = try #require(WheelhouseRemoteSessionProbe.sessions(inOutput: try probe(host, harnesses: harnesses), harnesses: harnesses))
        #expect(sessions.map(\.id) == ["abc-123"])
        #expect(sessions.map(\.harness.id) == ["kit"])
        #expect(sessions.first?.harness.resumeCommand(id: "abc-123") == "kit claude --resume abc-123")
        #expect(sessions.first?.title == nil)
    }

    @Test func findsASessionFileWrittenSinceTheAgentStartedInItsFolder() throws {
        let host = try Host()
        // 100 ticks a second: started now, give or take the test's own run time.
        let ticks = Int((Date().timeIntervalSince1970 - 1_000_000) * Double(sysconf(_SC_CLK_TCK)))
        try host.process(30, parent: 1, command: "codex", exe: "/usr/local/bin/codex", arguments: ["codex"], directory: "/srv/api", terminal: "term_c", startTicks: ticks)
        try host.write(
            """
            {"type":"session_meta","payload":{"id":"x","cwd":"/srv/other"}}
            {"type":"event_msg","payload":{"type":"user_message","message":"not this one"}}

            """,
            to: ".codex/sessions/2026/01/02/rollout-2026-01-02T03-04-05-11111111-2222-3333-4444-555555555555.jsonl")
        try host.write(
            """
            {"type":"session_meta","payload":{"id":"y","cwd":"/srv/api"}}
            {"type":"event_msg","payload":{"type":"user_message","message":"Add a health check"}}

            """,
            to: ".codex/sessions/2026/01/02/rollout-2026-01-02T03-04-06-99999999-2222-3333-4444-555555555555.jsonl")

        let sessions = try #require(WheelhouseRemoteSessionProbe.sessions(inOutput: try probe(host, harnesses: harnesses), harnesses: harnesses))
        #expect(sessions == [
            WheelhouseRemoteSession(
                id: "99999999-2222-3333-4444-555555555555", harness: WheelhouseHarness.builtIn[1], terminal: "term_c",
                directory: "/srv/api", title: "Add a health check"),
        ])
    }

    @Test func aHostWithoutAgentsAnswersWithNone() throws {
        let host = try Host()
        try host.process(10, parent: 1, command: "bash", exe: "/usr/bin/bash", arguments: ["-bash"], directory: "/", terminal: "term_a")
        #expect(WheelhouseRemoteSessionProbe.sessions(inOutput: try probe(host, harnesses: harnesses), harnesses: harnesses) == [])
    }

    @Test func whatIsNotTheProbesAnswerIsNoAnswer() {
        #expect(WheelhouseRemoteSessionProbe.sessions(inOutput: Data("bash: python3: command not found".utf8), harnesses: harnesses) == nil)
        #expect(WheelhouseRemoteSessionProbe.sessions(inOutput: Data(), harnesses: harnesses) == nil)
    }

    @Test func aSessionIdThatIsNotAPlainTokenIsLeftOut() {
        let output = Data("""
        {"processes": [{"pid": 5, "parent": 1, "name": "claude", "arguments": ["claude"], "startedAt": 1,
          "directory": "/w", "terminal": "term_a", "session": {"id": "x; rm -rf ~"}}]}
        """.utf8)
        #expect(WheelhouseRemoteSessionProbe.sessions(inOutput: output, harnesses: harnesses) == [])
    }

    @Test func resumesInTheSessionsFolder() {
        #expect(WheelhouseRemoteSessionProbe.resumeInput(resume: "claude --resume abc", directory: "/srv/it's here")
            == #"cd -- '/srv/it'\''s here' && claude --resume abc"#)
        #expect(WheelhouseRemoteSessionProbe.resumeInput(resume: "claude --resume abc", directory: nil) == "claude --resume abc")
        #expect(WheelhouseRemoteSessionProbe.resumeInput(resume: "claude --resume abc", directory: "relative") == "claude --resume abc")
    }

    @Test func quotesTheProbeCommandForTheRemoteShell() {
        let command = WheelhouseRemoteSessionProbe.command(harnesses: harnesses)
        #expect(command.hasPrefix("exec python3 '-c' 'import base64,sys;exec("))
        #expect(!command.contains("\n"))
    }

    /// Asks a real host. Runs only when `WHEELHOUSE_TEST_REMOTE_HOST` names an `ssh`
    /// destination that needs no password. Reads only.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WHEELHOUSE_TEST_REMOTE_HOST"] != nil))
    func aRealHostAnswers() throws {
        let destination = ProcessInfo.processInfo.environment["WHEELHOUSE_TEST_REMOTE_HOST"] ?? ""
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-T", "-o", "BatchMode=yes", "-o", "LogLevel=ERROR", "--", destination,
            WheelhouseRemoteSessionProbe.command(harnesses: harnesses),
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let sessions = try #require(WheelhouseRemoteSessionProbe.sessions(inOutput: data, harnesses: harnesses))
        for session in sessions {
            print("live: \(session.harness.id) \(session.id.prefix(8))… in \(session.terminal.prefix(10))… \(session.directory ?? "-") title: \(session.title?.prefix(40) ?? "-")")
        }
        print("live: \(sessions.count) session(s), \(data.count) bytes")
    }
}
