import Foundation
import Testing
@testable import WheelhouseCodeEditor

/// Runs the remote helper on this machine: the same program and protocol,
/// without the `ssh` in between.
@Suite struct RemoteProjectFilesTests {
    private func makeProject() throws -> (root: URL, files: RemoteProjectFiles) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-project-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("cmd/app"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try Data("package main\n".utf8).write(to: root.appendingPathComponent("cmd/app/main.go"))
        try Data("# readme\n".utf8).write(to: root.appendingPathComponent("README.md"))
        try Data("x".utf8).write(to: root.appendingPathComponent("a10.txt"))
        try Data("x".utf8).write(to: root.appendingPathComponent("a2.txt"))
        let files = RemoteProjectFiles(
            executable: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: RemoteProjectFiles.helperArguments(root: root.path),
            environment: nil
        )
        return (root, files)
    }

    private func failure(_ work: () async throws -> Void) async -> ProjectFileSystem.Failure? {
        do {
            try await work()
            return nil
        } catch {
            return error as? ProjectFileSystem.Failure
        }
    }

    @Test func listsReadsAndSaves() async throws {
        let (root, files) = try makeProject()
        defer {
            files.close()
            try? FileManager.default.removeItem(at: root)
        }
        #expect(try await files.list(root.path).map(\.name) == ["cmd", "a2.txt", "a10.txt", "README.md"])
        let path = root.path + "/cmd/app/main.go"
        let file = try await files.read(path)
        #expect(file.content == "package main\n")
        #expect(!file.isReadOnly)
        let saved = try await files.write("package app // ünïcode\n", to: path, expectedModified: file.modified)
        #expect(saved >= file.modified)
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "package app // ünïcode\n")
    }

    @Test func refusesToSaveOverAChangeMadeElsewhere() async throws {
        let (root, files) = try makeProject()
        defer {
            files.close()
            try? FileManager.default.removeItem(at: root)
        }
        let path = root.path + "/README.md"
        let file = try await files.read(path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: file.modified + 60)], ofItemAtPath: path
        )
        #expect(await failure { _ = try await files.write("# mine\n", to: path, expectedModified: file.modified) } == .changedOnDisk)
        _ = try await files.write("# mine\n", to: path, expectedModified: nil)
        #expect(try await files.read(path).content == "# mine\n")
    }

    @Test func searchesInFilesLikeTheLocalSearch() async throws {
        let (root, files) = try makeProject()
        defer {
            files.close()
            try? FileManager.default.removeItem(at: root)
        }
        try ProjectSearchFixture.write(into: root)
        let local = ProjectFileSystem(root: root.path)
        for query in ProjectSearchFixture.queries {
            let remote = try await files.search(query)
            let here = try local.search(query)
            #expect(remote.matches == here.matches, "query \(query)")
            #expect(remote.isComplete == here.isComplete)
        }
    }

    @Test func createsRenamesDeletesAndIndexes() async throws {
        let (root, files) = try makeProject()
        defer {
            files.close()
            try? FileManager.default.removeItem(at: root)
        }
        let folder = root.path + "/pkg"
        try await files.createDirectory(folder)
        try await files.createFile(folder + "/a.go")
        #expect(await failure { try await files.createFile(folder + "/a.go") } == .exists)
        try await files.move(folder + "/a.go", to: folder + "/b.go")
        #expect(try await files.index().paths == ["a2.txt", "a10.txt", "cmd/app/main.go", "pkg/b.go", "README.md"])
        try await files.trash(folder)
        #expect(!FileManager.default.fileExists(atPath: folder))
        #expect(try await files.index().isComplete)
    }

    @Test func staysInsideTheProject() async throws {
        let (root, files) = try makeProject()
        defer {
            files.close()
            try? FileManager.default.removeItem(at: root)
        }
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).go")
        try Data("package x\n".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        #expect(try await files.read(outside.path).isReadOnly)
        #expect(await failure { _ = try await files.write("y", to: outside.path, expectedModified: nil) } == .outsideProject)
        #expect(await failure { try await files.trash(outside.path) } == .outsideProject)
        #expect(await failure { try await files.trash(root.path) } == .outsideProject)
        #expect(await failure { try await files.move(root.path + "/README.md", to: outside.path + "2") } == .outsideProject)
        #expect(await failure { _ = try await files.list(root.deletingLastPathComponent().path) } == .outsideProject)
    }

    @Test func refusesBinaryFilesAndReportsMissingOnes() async throws {
        let (root, files) = try makeProject()
        defer {
            files.close()
            try? FileManager.default.removeItem(at: root)
        }
        try Data([0x89, 0x50, 0x00, 0x01]).write(to: root.appendingPathComponent("image.bin"))
        #expect(await failure { _ = try await files.read(root.path + "/image.bin") } == .notText)
        #expect(await failure { _ = try await files.read(root.path + "/gone.go") } == .unreadable("unreadable"))
    }

    @Test func startsAgainAfterTheConnectionEnds() async throws {
        let (root, files) = try makeProject()
        defer {
            files.close()
            try? FileManager.default.removeItem(at: root)
        }
        #expect(try await files.read(root.path + "/README.md").content == "# readme\n")
        files.close()
        #expect(try await files.read(root.path + "/README.md").content == "# readme\n")
    }

    @Test func aHostThatCannotBeReachedFailsTheRequest() async {
        let files = RemoteProjectFiles(executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: [], environment: nil)
        #expect(await failure { _ = try await files.list("/") } != nil)
    }

    @Test func quotesTheHelperCommandForTheRemoteShell() {
        let command = RemoteProjectFiles.helperCommand(root: "/home/me/it's here")
        #expect(command.hasPrefix("exec python3 '-u' '-c' 'import base64,sys;"))
        #expect(command.hasSuffix(" '/home/me/it'\\''s here'"))
    }
}

@Suite struct RemoteLanguageServerTests {
    private let host = CodeEditorRemoteHost(name: "box", sshArguments: ["-T", "--", "box"])

    @Test func runsTheServerThroughTheLoginShellInTheProjectFolder() {
        let definition = LanguageServerDefinition(command: ["gopls", "-remote=auto"], rootMarkers: ["go.mod"])
        let launch = LanguageServerLaunch.remote(definition, root: "/home/me/my repo", host: host)
        #expect(launch.executable.path == "/usr/bin/ssh")
        #expect(launch.arguments == [
            "-T", "--", "box",
            #"cd '/home/me/my repo' && exec "${SHELL:-/bin/sh}" -lc 'exec '\''gopls'\'' '\''-remote=auto'\'''"#,
        ])
        #expect(launch.directory == nil)
        #expect(launch.root == "/home/me/my repo")
        #expect(launch.label == "box:/home/me/my repo")
    }

    @Test func aRemoteServerIsNotGivenThisMacsProcessNumber() throws {
        let request: [String: Any] = ["method": "initialize", "params": ["rootUri": NSNull()]]
        let completed = LanguageServerRegistry.completingInitialize(request, rootDirectory: "/home/me/repo", processIdentifier: nil)
        let params = try #require(completed["params"] as? [String: Any])
        #expect(params["processId"] is NSNull)
        #expect(params["rootUri"] as? String == "file:///home/me/repo/")
    }

    @Test func stepsOverWhatAShellPrintsBeforeTheServerStarts() {
        var framer = LanguageServerMessageFramer()
        let body = Data(#"{"id":1}"#.utf8)
        var stream = Data("Welcome to box\nLast login: today\n".utf8)
        stream.append(LanguageServerMessageFramer.frame(body))
        #expect(framer.append(stream) == [body])
    }

    @Test func remembersARemoteFolderApartFromALocalOneWithTheSamePath() {
        let name = "project-session-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        ProjectEditorSession(openFiles: ["/work/a.go"]).save(root: "/work", host: "box", to: defaults)
        #expect(ProjectEditorSession.load(root: "/work", from: defaults) == ProjectEditorSession())
        #expect(ProjectEditorSession.load(root: "/work", host: "box", from: defaults).openFiles == ["/work/a.go"])
    }
}

/// Talks to a real host. Runs only when `WHEELHOUSE_TEST_REMOTE_HOST` names
/// an `ssh` destination that needs no password and `WHEELHOUSE_TEST_REMOTE_ROOT`
/// an existing Go module folder on it. Reads only.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["WHEELHOUSE_TEST_REMOTE_HOST"] != nil))
struct RemoteHostLiveTests {
    private var host: CodeEditorRemoteHost {
        let destination = ProcessInfo.processInfo.environment["WHEELHOUSE_TEST_REMOTE_HOST"] ?? ""
        return CodeEditorRemoteHost(
            name: destination,
            sshArguments: ["-T", "-o", "BatchMode=yes", "-o", "LogLevel=ERROR", "--", destination]
        )
    }

    private var root: String {
        ProcessInfo.processInfo.environment["WHEELHOUSE_TEST_REMOTE_ROOT"] ?? ""
    }

    @Test func listsAndReadsOverSSH() async throws {
        let files = RemoteProjectFiles(root: root, host: host)
        defer { files.close() }
        let entries = try await files.list(root)
        #expect(entries.contains { $0.name == "go.mod" })
        #expect(try await files.read(root + "/go.mod").content.contains("module "))
        let clock = ContinuousClock()
        let elapsed = try await clock.measure { _ = try await files.list(root) }
        print("one request on the open connection: \(elapsed)")
        #expect(!(try await files.index().paths.isEmpty))
    }

    /// Writes, so it only runs when `WHEELHOUSE_TEST_REMOTE_SCRATCH` names an
    /// empty folder on the host that it may fill and empty again.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WHEELHOUSE_TEST_REMOTE_SCRATCH"] != nil))
    func editsFilesOverSSH() async throws {
        let scratch = ProcessInfo.processInfo.environment["WHEELHOUSE_TEST_REMOTE_SCRATCH"] ?? ""
        let files = RemoteProjectFiles(root: scratch, host: host)
        defer { files.close() }
        try await files.createDirectory(scratch + "/pkg")
        try await files.createFile(scratch + "/pkg/a.txt")
        let empty = try await files.read(scratch + "/pkg/a.txt")
        #expect(empty.content.isEmpty)
        #expect(!empty.isReadOnly)
        let saved = try await files.write("héllo\n", to: scratch + "/pkg/a.txt", expectedModified: empty.modified)
        do {
            _ = try await files.write("stale\n", to: scratch + "/pkg/a.txt", expectedModified: empty.modified - 5)
            Issue.record("a save over a newer file went through")
        } catch {
            #expect(error as? ProjectFileSystem.Failure == .changedOnDisk)
        }
        try await files.move(scratch + "/pkg/a.txt", to: scratch + "/pkg/b.txt")
        let moved = try await files.read(scratch + "/pkg/b.txt")
        #expect(moved.content == "héllo\n")
        #expect(abs(moved.modified - saved) < 0.001)
        #expect(try await files.index().paths == ["pkg/b.txt"])
        try await files.trash(scratch + "/pkg")
        #expect(try await files.list(scratch).isEmpty)
    }

    @Test func aLanguageServerAnswersOverSSH() async throws {
        let definition = try #require(LanguageServerRegistry.definition(forFileExtension: "go", overrides: nil))
        let launch = LanguageServerLaunch.remote(definition, root: root, host: host)
        let (answers, continuation) = AsyncStream<Data>.makeStream()
        let process = LanguageServerProcess(
            executable: launch.executable,
            arguments: launch.arguments,
            environment: launch.environment,
            directory: launch.directory,
            onMessage: { continuation.yield($0) },
            onExit: { continuation.finish() }
        )
        try process.start()
        defer { process.stop() }
        let request = LanguageServerRegistry.completingInitialize(
            ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["capabilities": [String: Any]()]],
            rootDirectory: root,
            processIdentifier: nil
        )
        process.send(try JSONSerialization.data(withJSONObject: request))
        var answer: [String: Any]?
        for await body in answers {
            let message = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            if message?["id"] as? Int == 1 {
                answer = message
                break
            }
        }
        let result = try #require(answer?["result"] as? [String: Any])
        #expect(result["capabilities"] != nil)
        print("server: \(result["serverInfo"] ?? "?")")
    }
}
