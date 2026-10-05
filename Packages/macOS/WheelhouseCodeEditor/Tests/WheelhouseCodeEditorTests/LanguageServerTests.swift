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
