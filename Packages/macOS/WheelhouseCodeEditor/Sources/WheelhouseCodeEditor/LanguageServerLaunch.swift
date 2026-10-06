import Foundation

/// How to start one language server: on this Mac as a child process, or on a
/// remote host as the command of an `ssh` process, whose standard streams
/// then carry the server's.
struct LanguageServerLaunch: Sendable {
    var executable: URL
    var arguments: [String]
    var environment: [String: String]
    /// Working directory of the local process; `nil` leaves it alone.
    var directory: URL?
    /// The folder the server works in, on the machine it runs on.
    var root: String
    /// The root, with the host for a remote server; for the log.
    var label: String

    /// `nil` when the server is not installed.
    static func local(_ definition: LanguageServerDefinition, root: String) async -> LanguageServerLaunch? {
        let searchPath = await LanguageServerEnvironment.shared.searchPath()
        guard let executable = LanguageServerEnvironment.executable(named: definition.command[0], searchPath: searchPath) else {
            return nil
        }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath
        return LanguageServerLaunch(
            executable: executable,
            arguments: Array(definition.command.dropFirst()),
            environment: environment,
            directory: URL(fileURLWithPath: root, isDirectory: true),
            root: root,
            label: root
        )
    }

    /// Whether the server exists there is only known once it runs: a host
    /// without it ends the process at once.
    static func remote(_ definition: LanguageServerDefinition, root: String, host: CodeEditorRemoteHost) -> LanguageServerLaunch {
        LanguageServerLaunch(
            executable: URL(fileURLWithPath: "/usr/bin/ssh"),
            arguments: host.sshArguments + [LanguageServerRegistry.remoteCommand(definition.command, root: root)],
            environment: host.environment ?? ProcessInfo.processInfo.environment,
            directory: nil,
            root: root,
            label: "\(host.name):\(root)"
        )
    }
}
