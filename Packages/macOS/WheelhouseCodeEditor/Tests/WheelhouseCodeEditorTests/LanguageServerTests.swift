import Foundation
import Testing
@testable import WheelhouseCodeEditor

@Suite struct LanguageServerMessageFramerTests {
    @Test func framesAndSplitsMessages() {
        let first = Data(#"{"id":1}"#.utf8)
        let second = Data(#"{"method":"é"}"#.utf8)
        var stream = LanguageServerMessageFramer.frame(first)
        stream.append(LanguageServerMessageFramer.frame(second))

        var framer = LanguageServerMessageFramer()
        #expect(framer.append(stream) == [first, second])
    }

    @Test func waitsForTheRestOfAMessage() {
        let body = Data(#"{"jsonrpc":"2.0","id":7,"result":null}"#.utf8)
        let stream = LanguageServerMessageFramer.frame(body)
        var framer = LanguageServerMessageFramer()
        #expect(framer.append(stream.prefix(10)).isEmpty)
        #expect(framer.append(stream.dropFirst(10).prefix(20)).isEmpty)
        #expect(framer.append(stream.dropFirst(30)) == [body])
    }

    @Test func acceptsExtraHeadersAndAnyHeaderCase() {
        let stream = Data("content-length: 2\r\nContent-Type: application/vscode-jsonrpc\r\n\r\n{}".utf8)
        var framer = LanguageServerMessageFramer()
        #expect(framer.append(stream) == [Data("{}".utf8)])
    }
}

@Suite struct LanguageServerRegistryTests {
    @Test func goUsesTheSharedGoplsDaemon() {
        let definition = LanguageServerRegistry.definition(forFileExtension: "GO", overrides: nil)
        #expect(definition?.command == ["gopls", "-remote=auto"])
        #expect(LanguageServerRegistry.definition(forFileExtension: "txt", overrides: nil) == nil)
    }

    @Test func storedSettingsAddReplaceAndTurnOffServers() {
        let overrides: [String: Any] = [
            "rs": ["command": ["rust-analyzer"], "rootMarkers": ["Cargo.toml"]],
            "go": ["command": ["/opt/gopls"]],
            "py": ["command": [String]()],
        ]
        #expect(LanguageServerRegistry.definition(forFileExtension: "rs", overrides: overrides)
            == LanguageServerDefinition(command: ["rust-analyzer"], rootMarkers: ["Cargo.toml"]))
        #expect(LanguageServerRegistry.definition(forFileExtension: "go", overrides: overrides)
            == LanguageServerDefinition(command: ["/opt/gopls"], rootMarkers: ["go.work", "go.mod"]))
        #expect(LanguageServerRegistry.definition(forFileExtension: "py", overrides: overrides) == nil)
        #expect(LanguageServerRegistry.definition(forFileExtension: "go", overrides: ["go": ["command": [String]()]]) == nil)
    }

    @Test func rootIsTheNearestPreferredMarker() {
        let existing: Set<String> = ["/src/go.work", "/src/app/go.mod", "/other/svc/go.mod"]
        let fileExists: (String) -> Bool = { existing.contains($0) }
        #expect(LanguageServerRegistry.rootDirectory(
            forFile: "/src/app/cmd/main.go", markers: ["go.work", "go.mod"], fileExists: fileExists
        ) == "/src")
        #expect(LanguageServerRegistry.rootDirectory(
            forFile: "/other/svc/pkg/a/a.go", markers: ["go.work", "go.mod"], fileExists: fileExists
        ) == "/other/svc")
        #expect(LanguageServerRegistry.rootDirectory(
            forFile: "/tmp/scratch/x.go", markers: ["go.work", "go.mod"], fileExists: fileExists
        ) == "/tmp/scratch")
    }

    @Test func initializeGetsTheRootAndProcess() throws {
        let message: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": ["processId": NSNull(), "rootUri": NSNull(), "capabilities": ["a": 1]],
        ]
        let completed = LanguageServerRegistry.completingInitialize(message, rootDirectory: "/src/my app", processIdentifier: 42)
        let params = try #require(completed["params"] as? [String: Any])
        #expect(params["processId"] as? Int == 42)
        #expect(params["rootUri"] as? String == "file:///src/my%20app/")
        #expect((params["workspaceFolders"] as? [[String: String]])?.first?["name"] == "my app")
        #expect((params["capabilities"] as? [String: Int]) == ["a": 1])
    }

    @Test func otherMessagesPassThrough() {
        let message: [String: Any] = ["jsonrpc": "2.0", "method": "initialized", "params": [String: Any]()]
        let completed = LanguageServerRegistry.completingInitialize(message, rootDirectory: "/src", processIdentifier: 42)
        #expect((completed["params"] as? [String: Any])?.isEmpty == true)
    }
}

@Suite struct LanguageServerEnvironmentTests {
    @Test func readsThePathBetweenTheMarkers() {
        let output = "motd from an rc file\n__WHEELHOUSE_PATH__/a/bin:/b/bin__WHEELHOUSE_PATH__\n"
        #expect(LanguageServerEnvironment.path(inShellOutput: output) == "/a/bin:/b/bin")
        #expect(LanguageServerEnvironment.path(inShellOutput: "no markers") == nil)
    }

    @Test func joinsSearchPathsWithoutDuplicates() {
        #expect(LanguageServerEnvironment.joined(["/a:/b", nil, "/b::/c"]) == "/a:/b:/c")
    }

    @Test func findsExecutablesOnTheSearchPath() {
        #expect(LanguageServerEnvironment.executable(named: "ls", searchPath: "/nonexistent:/bin")?.path == "/bin/ls")
        #expect(LanguageServerEnvironment.executable(named: "/bin/ls", searchPath: "") != nil)
        #expect(LanguageServerEnvironment.executable(named: "no-such-server", searchPath: "/bin") == nil)
    }

    @Test func runsAServerAndExchangesMessages() async throws {
        // `cat` echoes each framed message back, standing in for a server.
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        let process = LanguageServerProcess(
            executable: URL(fileURLWithPath: "/bin/cat"), arguments: [], environment: [:],
            directory: URL(fileURLWithPath: "/tmp"),
            onMessage: { continuation.yield($0) },
            onExit: { continuation.finish() }
        )
        try process.start()
        let body = Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8)
        process.send(body)
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == body)
        process.stop()
        #expect(await iterator.next() == nil)
    }
}

@Suite struct ProjectFileSystemTests {
    private func makeProject() throws -> (root: URL, files: ProjectFileSystem) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("cmd/app"), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try Data("package main\n".utf8).write(to: root.appendingPathComponent("cmd/app/main.go"))
        try Data("# readme\n".utf8).write(to: root.appendingPathComponent("README.md"))
        try Data("x".utf8).write(to: root.appendingPathComponent("a10.txt"))
        try Data("x".utf8).write(to: root.appendingPathComponent("a2.txt"))
        return (root, ProjectFileSystem(root: root.path))
    }

    @Test func listsFoldersFirstAndHidesGitData() throws {
        let (root, files) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try files.list(root.path).map(\.name) == ["cmd", "a2.txt", "a10.txt", "README.md"])
        #expect(try files.list(root.path).first?.isDirectory == true)
    }

    @Test func readsAndSavesFilesInTheProject() throws {
        let (root, files) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.path + "/cmd/app/main.go"
        let file = try files.read(path)
        #expect(file.content == "package main\n")
        #expect(!file.isReadOnly)
        _ = try files.write("package app\n", to: path, expectedModified: file.modified)
        #expect(try files.read(path).content == "package app\n")
    }

    @Test func refusesToSaveOverAChangeMadeElsewhere() throws {
        let (root, files) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.path + "/README.md"
        let file = try files.read(path)
        try Data("# changed elsewhere\n".utf8).write(to: URL(fileURLWithPath: path))
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: file.modified + 60)], ofItemAtPath: path
        )
        #expect(throws: ProjectFileSystem.Failure.changedOnDisk) {
            try files.write("# mine\n", to: path, expectedModified: file.modified)
        }
        _ = try files.write("# mine\n", to: path, expectedModified: nil)
        #expect(try files.read(path).content == "# mine\n")
    }

    @Test func filesOutsideTheProjectAreReadOnly() throws {
        let (root, files) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).go")
        try Data("package x\n".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        #expect(try files.read(outside.path).isReadOnly)
        #expect(throws: ProjectFileSystem.Failure.outsideProject) {
            try files.write("package y\n", to: outside.path, expectedModified: nil)
        }
        #expect(throws: ProjectFileSystem.Failure.outsideProject) { try files.list(outside.deletingLastPathComponent().path) }
        #expect(!files.contains(root.path + "-sibling/file.go"))
    }

    @Test func withoutAProjectFilesCanOnlyBeRead() throws {
        let (root, _) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = ProjectFileSystem(root: nil)
        let path = root.path + "/README.md"
        #expect(try files.read(path).content == "# readme\n")
        #expect(try files.read(path).isReadOnly)
        #expect(throws: ProjectFileSystem.Failure.outsideProject) {
            try files.write("# mine\n", to: path, expectedModified: nil)
        }
        #expect(throws: ProjectFileSystem.Failure.outsideProject) { try files.list(root.path) }
    }

    @Test func refusesBinaryFiles() throws {
        let (root, files) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.path + "/image.bin"
        try Data([0x89, 0x50, 0x00, 0x01]).write(to: URL(fileURLWithPath: path))
        #expect(throws: ProjectFileSystem.Failure.notText) { try files.read(path) }
    }
}
