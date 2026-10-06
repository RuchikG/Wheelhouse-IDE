import Foundation

/// A folder shown in a project editor: a file tree with the files opened from it.
public struct CodeEditorProject: Equatable, Sendable {
    /// Absolute path of the folder, on the machine that holds it.
    public var rootPath: String
    /// The machine that holds the folder; `nil` for this Mac.
    public var remote: CodeEditorRemoteHost?

    public init(rootPath: String, remote: CodeEditorRemoteHost? = nil) {
        self.rootPath = rootPath
        self.remote = remote
    }
}

/// Another machine, reached with `ssh`, that holds a project's files and runs
/// its language servers.
public struct CodeEditorRemoteHost: Equatable, Sendable {
    /// What the user calls the host; shown in the editor and used to tell hosts apart.
    public var name: String
    /// Everything `/usr/bin/ssh` needs before the remote command, destination included.
    public var sshArguments: [String]
    /// The environment for `ssh`; `nil` uses the app's.
    public var environment: [String: String]?

    public init(name: String, sshArguments: [String], environment: [String: String]? = nil) {
        self.name = name
        self.sshArguments = sshArguments
        self.environment = environment
    }

    /// `text` as one word of a POSIX shell command.
    static func shellWord(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// A host reached by its `ssh` destination alone, the way `ssh <destination>`
    /// reaches it from a terminal: `~/.ssh/config` supplies the rest. The
    /// connections the editor opens to it share one authenticated session.
    public static func host(destination: String) -> CodeEditorRemoteHost {
        // A control socket path is short; the temporary directory would not fit.
        let sockets = "/tmp/wheelhouse-ssh-\(getuid())"
        try? FileManager.default.createDirectory(
            atPath: sockets, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        return CodeEditorRemoteHost(
            name: destination,
            sshArguments: [
                "-T",
                "-o", "BatchMode=yes",
                "-o", "RemoteCommand=none",
                "-o", "RequestTTY=no",
                "-o", "ConnectTimeout=10",
                "-o", "ServerAliveInterval=15",
                "-o", "ServerAliveCountMax=3",
                "-o", "ControlMaster=auto",
                "-o", "ControlPersist=60",
                "-o", "ControlPath=\(sockets)/%C",
                "-o", "LogLevel=ERROR",
                "--", destination,
            ]
        )
    }

    /// Why a folder on the host could not be opened, in the host's own words.
    public struct FolderFailure: Error, Equatable, Sendable {
        public var message: String
    }

    /// The real absolute path of `folder` on the host. `folder` may start
    /// with `~`. Fails when the host cannot be reached without a prompt or
    /// the folder does not exist.
    public func resolveFolder(_ folder: String) async -> Result<String, FolderFailure> {
        let trimmed = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        let word: String
        if trimmed == "~" || trimmed.hasPrefix("~/") {
            word = "\"$HOME\"" + Self.shellWord(String(trimmed.dropFirst()))
        } else {
            word = Self.shellWord(trimmed)
        }
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = sshArguments + ["cd -- \(word) && pwd -P"]
        if let environment { process.environment = environment }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { ended in
                let path = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let complaint = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if ended.terminationStatus == 0, path.hasPrefix("/") {
                    continuation.resume(returning: .success(path))
                } else {
                    continuation.resume(returning: .failure(FolderFailure(message: complaint)))
                }
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: .failure(FolderFailure(message: error.localizedDescription)))
            }
        }
    }
}
