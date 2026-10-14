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
            directory: String, terminal: String?, startTicks: Int = 0, role: String? = nil
        ) throws {
            let folder = proc.appendingPathComponent(String(pid), isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var environment = ["HOME=/home/someone", "SECRET_TOKEN=do-not-read"]
            if let terminal { environment.append("\(WheelhouseRemoteSessionProbe.terminalVariable)=\(terminal)") }
            if let role { environment.append("\(WheelhouseRemoteSessionProbe.roleVariable)=\(role)") }
            try Data((environment.joined(separator: "\0") + "\0").utf8).write(to: folder.appendingPathComponent("environ"))
            let rest = ["S", String(parent)] + Array(repeating: "0", count: 17) + [String(startTicks), "0"]
            try Data("\(pid) (\(command)) \(rest.joined(separator: " "))\n".utf8)
                .write(to: folder.appendingPathComponent("stat"))
            try Data((arguments.joined(separator: "\0") + "\0").utf8).write(to: folder.appendingPathComponent("cmdline"))
            try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("exe").path, withDestinationPath: exe)
            try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("cwd").path, withDestinationPath: directory)
        }
    }

    private func probe(_ host: Host, harnesses: [WheelhouseHarness], files: [String] = []) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = WheelhouseRemoteSessionProbe.arguments(harnesses: harnesses, files: files) + [host.proc.path]
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
                directory: "/srv/app", title: "Fix the cart totals",
                transcript: host.home.path + "/.claude/projects/-srv-app/0a1b2c3d-1111-2222-3333-444455556666.jsonl"),
        ])
    }

    @Test func tellsTheRoleAnAgentWasStartedIn() throws {
        let host = try Host()
        try host.process(10, parent: 1, command: "bash", exe: "/usr/bin/bash", arguments: ["-bash"], directory: "/srv/app", terminal: "term_a")
        try host.process(
            11, parent: 10, command: "claude", exe: "/opt/claude/claude", arguments: ["claude"], directory: "/srv/app",
            terminal: "term_a", role: "project")
        try host.process(20, parent: 1, command: "bash", exe: "/usr/bin/bash", arguments: ["-bash"], directory: "/srv/app", terminal: "term_b")
        try host.process(
            21, parent: 20, command: "claude", exe: "/opt/claude/claude", arguments: ["claude"], directory: "/srv/app",
            terminal: "term_b", role: "not a token")
        try host.write(#"{"sessionId": "abc-1"}"#, to: ".claude/sessions/11.json")
        try host.write(#"{"sessionId": "abc-2"}"#, to: ".claude/sessions/21.json")

        let sessions = try #require(WheelhouseRemoteSessionProbe.sessions(inOutput: try probe(host, harnesses: harnesses), harnesses: harnesses))
        #expect(sessions.map(\.id) == ["abc-1", "abc-2"])
        #expect(sessions.map(\.role) == ["project", nil])
    }

    @Test func reportsTheHomeFolderAndTheFilesAskedAbout() throws {
        let host = try Host()
        try host.write("# Cart: project memory\n\nKept by the project agent for every agent that works on this project. Keep it short:\nwhat the next agent needs to start work without asking.\n\n## Open\n", to: ".wheelhouse/memory/cart.md")
        try host.write("# Shop: project memory\n\n## Where it stands\n\nIn review.\n", to: ".wheelhouse/memory/shop.md")

        let output = try probe(host, harnesses: harnesses, files: [".wheelhouse/memory/cart.md", ".wheelhouse/memory/shop.md", ".wheelhouse/memory/none.md"])
        let answer = try #require(WheelhouseRemoteSessionProbe.answer(inOutput: output, harnesses: harnesses))
        #expect(answer.home == host.home.path)
        #expect(answer.files.keys.sorted() == [".wheelhouse/memory/cart.md", ".wheelhouse/memory/shop.md"])
        #expect(answer.files[".wheelhouse/memory/cart.md"]?.hasNotes == false)
        #expect(answer.files[".wheelhouse/memory/shop.md"]?.hasNotes == true)
        #expect((answer.files[".wheelhouse/memory/shop.md"]?.modifiedAt ?? 0) > Date().timeIntervalSince1970 - 60)
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
                directory: "/srv/api", title: "Add a health check",
                transcript: host.home.path
                    + "/.codex/sessions/2026/01/02/rollout-2026-01-02T03-04-06-99999999-2222-3333-4444-555555555555.jsonl"),
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

    @Test func resumesInTheSessionsFolderThroughTheLoginShell() throws {
        let shell = #"exec "${SHELL:-/bin/sh}" -l"#
        let inFolder = WheelhouseRemoteSessionProbe.resumeArguments(resume: "claude --resume abc", directory: "/srv/it's here")
        #expect(inFolder == [
            "/bin/sh", "-c", #"exec "${SHELL:-/bin/sh}" -lic "$1""#, "wheelhouse-resume",
            #"cd -- '/srv/it'\''s here' && claude --resume abc; "# + shell,
        ])
        #expect(WheelhouseRemoteSessionProbe.resumeArguments(resume: "claude --resume abc", directory: nil).last
            == "claude --resume abc; " + shell)
        #expect(WheelhouseRemoteSessionProbe.resumeArguments(resume: "claude --resume abc", directory: "relative").last
            == "claude --resume abc; " + shell)

        // Run for real with a stand-in shell: the command arrives whole, in the folder.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("it's here \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let arguments = WheelhouseRemoteSessionProbe.resumeArguments(
            resume: #"printf '%s|' "$PWD" "a b""#, directory: folder.path)
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        // `true` as the shell that follows ends the run.
        process.environment = ["SHELL": "/bin/sh", "PATH": "/usr/bin:/bin"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let printed = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(printed.hasSuffix("\(folder.lastPathComponent)|a b|"))
    }

    @Test func startsInARoleAndAFolderUnderTheHomeFolder() throws {
        let shell = #"exec "${SHELL:-/bin/sh}" -l"#
        let started = WheelhouseRemoteSessionProbe.startArguments(
            start: "claude 'New agent'", directory: "~/work/it's", role: "project")
        #expect(started.last == #"export WHEELHOUSE_ROLE=project; cd -- "$HOME"/'work/it'\''s' && claude 'New agent'; unset WHEELHOUSE_ROLE; "# + shell)
        #expect(WheelhouseRemoteSessionProbe.startArguments(start: "codex", directory: "~", role: "bad role").last
            == #"cd -- "$HOME" && codex; "# + shell)

        // Run for real: the role reaches the command and not the shell that follows.
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("home \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("work"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let arguments = WheelhouseRemoteSessionProbe.startArguments(
            start: #"printf '%s|' "$PWD" "$WHEELHOUSE_ROLE""#, directory: "~/work", role: "project")
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        process.environment = ["SHELL": "/bin/sh", "PATH": "/usr/bin:/bin", "HOME": home.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let printed = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(printed.hasSuffix("/work|project|"))
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
