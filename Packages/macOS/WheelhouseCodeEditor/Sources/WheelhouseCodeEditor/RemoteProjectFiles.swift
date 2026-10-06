import Foundation

/// A project's files on a remote host. One `ssh` process stays open for the
/// life of the editor and runs `RemoteProjectHelperScript` there; each
/// operation is a line to it and a line back, which costs one network round
/// trip instead of a new connection.
final class RemoteProjectFiles: ProjectFiles, @unchecked Sendable {
    private typealias Reply = Result<[String: Any], ProjectFileSystem.Failure>

    private let executable: URL
    private let arguments: [String]
    private let environment: [String: String]?
    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var unread = Data()
    private var nextIdentifier = 1
    /// Requests without a reply yet, each with the connection it went out on.
    private var waiting: [Int: (continuation: CheckedContinuation<SendableReply, Never>, connection: Process?)] = [:]

    /// A reply crosses from the reader thread to the awaiting task.
    private struct SendableReply: @unchecked Sendable {
        var value: Reply
    }

    /// - Parameters:
    ///   - executable: The program that reaches the helper; `ssh` outside tests.
    ///   - arguments: Its arguments, ending in the command that starts the helper.
    init(executable: URL, arguments: [String], environment: [String: String]?) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }

    convenience init(root: String, host: CodeEditorRemoteHost) {
        self.init(
            executable: URL(fileURLWithPath: "/usr/bin/ssh"),
            arguments: host.sshArguments + [Self.helperCommand(root: root)],
            environment: host.environment
        )
    }

    /// The arguments that make `python3` run the helper for `root`. The
    /// program travels base64-encoded so no quoting of it can go wrong.
    static func helperArguments(root: String) -> [String] {
        let program = Data(RemoteProjectHelperScript.source.utf8).base64EncodedString()
        return ["-u", "-c", "import base64,sys;exec(base64.b64decode(sys.argv[1]).decode())", program, root]
    }

    /// The remote shell command that starts the helper for `root`.
    static func helperCommand(root: String) -> String {
        "exec python3 " + helperArguments(root: root).map(CodeEditorRemoteHost.shellWord).joined(separator: " ")
    }

    // MARK: ProjectFiles

    func list(_ directory: String) async throws -> [ProjectFileSystem.Entry] {
        let reply = try await request("list", path: directory)
        return (reply["entries"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let name = entry["name"] as? String else { return nil }
            return ProjectFileSystem.Entry(name: name, isDirectory: entry["isDirectory"] as? Bool ?? false)
        }
    }

    func read(_ path: String) async throws -> ProjectFileSystem.File {
        let reply = try await request("read", path: path)
        guard let content = reply["content"] as? String else { throw ProjectFileSystem.Failure.unreadable(path) }
        return ProjectFileSystem.File(
            content: content,
            modified: reply["modified"] as? Double ?? 0,
            isReadOnly: reply["readOnly"] as? Bool ?? false
        )
    }

    func write(_ content: String, to path: String, expectedModified: Double?) async throws -> Double {
        var fields: [String: Any] = ["content": content]
        fields["modified"] = expectedModified
        return try await request("write", path: path, fields: fields)["modified"] as? Double ?? 0
    }

    func createFile(_ path: String) async throws {
        _ = try await request("createFile", path: path)
    }

    func createDirectory(_ path: String) async throws {
        _ = try await request("createDirectory", path: path)
    }

    func move(_ path: String, to destination: String) async throws {
        _ = try await request("move", path: path, fields: ["to": destination])
    }

    func trash(_ path: String) async throws {
        _ = try await request("delete", path: path)
    }

    func index() async throws -> (paths: [String], isComplete: Bool) {
        let reply = try await request("index", path: "/")
        return (reply["paths"] as? [String] ?? [], reply["complete"] as? Bool ?? true)
    }

    func close() {
        lock.lock()
        let process = self.process
        let input = self.input
        self.process = nil
        self.input = nil
        lock.unlock()
        try? input?.close()
        if process?.isRunning == true {
            process?.terminate()
        }
    }

    // MARK: Connection

    private func request(_ operation: String, path: String, fields: [String: Any] = [:]) async throws -> [String: Any] {
        var message = fields
        message["op"] = operation
        message["path"] = path
        let reply = await withCheckedContinuation { (continuation: CheckedContinuation<SendableReply, Never>) in
            lock.lock()
            let identifier = nextIdentifier
            nextIdentifier += 1
            message["id"] = identifier
            let handle = connectedInput()
            waiting[identifier] = (continuation, process)
            lock.unlock()
            guard let handle, let line = try? JSONSerialization.data(withJSONObject: message) else {
                finish(identifier, with: .failure(.unreadable("no connection to the remote host")))
                return
            }
            do {
                try handle.write(contentsOf: line + Data("\n".utf8))
            } catch {
                finish(identifier, with: .failure(.unreadable(error.localizedDescription)))
            }
        }
        return try reply.value.get()
    }

    /// The helper's input, starting the helper first when it is not running.
    /// Call with the lock held.
    private func connectedInput() -> FileHandle? {
        if let input, process?.isRunning == true { return input }
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.receive(data)
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            CodeEditorLog.bridge.notice("remote files: \(String(decoding: data, as: UTF8.self), privacy: .public)")
        }
        process.terminationHandler = { [weak self] ended in
            self?.connectionEnded(ended)
        }
        do {
            try process.run()
        } catch {
            CodeEditorLog.bridge.error("remote files: could not start ssh: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        // A write after the connection dropped must fail, not end the app.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        unread = Data()
        self.process = process
        self.input = input.fileHandleForWriting
        return self.input
    }

    private func receive(_ data: Data) {
        lock.lock()
        unread.append(data)
        var lines: [Data] = []
        while let newline = unread.firstIndex(of: 0x0A) {
            lines.append(Data(unread[unread.startIndex..<newline]))
            unread.removeSubrange(unread.startIndex...newline)
        }
        lock.unlock()
        for line in lines {
            guard let reply = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let identifier = reply["id"] as? Int else { continue }
            if reply["ok"] as? Bool == true {
                finish(identifier, with: .success(reply))
            } else {
                finish(identifier, with: .failure(Self.failure(named: reply["error"] as? String)))
            }
        }
    }

    /// A connection is gone: what was still waiting on it fails, and the next
    /// request starts a new one.
    private func connectionEnded(_ ended: Process) {
        lock.lock()
        if process === ended {
            process = nil
            input = nil
        }
        let abandoned = waiting.filter { $0.value.connection === ended }.map(\.key)
        lock.unlock()
        for identifier in abandoned {
            finish(identifier, with: .failure(.unreadable("the connection to the remote host ended")))
        }
    }

    private func finish(_ identifier: Int, with reply: Reply) {
        lock.lock()
        let continuation = waiting.removeValue(forKey: identifier)?.continuation
        lock.unlock()
        continuation?.resume(returning: SendableReply(value: reply))
    }

    private static func failure(named name: String?) -> ProjectFileSystem.Failure {
        switch name {
        case "outsideProject": return .outsideProject
        case "notText": return .notText
        case "tooLarge": return .tooLarge
        case "changedOnDisk": return .changedOnDisk
        case "exists": return .exists
        default: return .unreadable(name ?? "unknown")
        }
    }
}
