import Foundation

/// How to run the language server for one kind of file.
struct LanguageServerDefinition: Equatable, Sendable {
    /// Executable name or path, then its arguments.
    var command: [String]
    /// Files that mark a project root, in order of preference.
    var rootMarkers: [String]
}

/// Language servers by lowercased file extension.
enum LanguageServerRegistry {
    /// UserDefaults key holding additions and replacements:
    /// `{ "<extension>": { "command": ["server", "arg"], "rootMarkers": ["marker"] } }`.
    /// An empty `command` turns a built-in server off.
    static let defaultsKey = "wheelhouse.languageServers"

    static let builtIn: [String: LanguageServerDefinition] = [
        // -remote=auto makes every editor a thin client of one shared gopls
        // daemon, so files of the same module share one loaded workspace.
        "go": LanguageServerDefinition(command: ["gopls", "-remote=auto"], rootMarkers: ["go.work", "go.mod"]),
    ]

    static func definition(forFileExtension fileExtension: String, overrides: [String: Any]?) -> LanguageServerDefinition? {
        let key = fileExtension.lowercased()
        guard let override = overrides?[key] as? [String: Any] else { return builtIn[key] }
        let command = (override["command"] as? [String] ?? []).filter { !$0.isEmpty }
        guard !command.isEmpty else { return nil }
        return LanguageServerDefinition(
            command: command,
            rootMarkers: override["rootMarkers"] as? [String] ?? builtIn[key]?.rootMarkers ?? []
        )
    }

    /// The nearest ancestor of `filePath` holding the most preferred marker
    /// found; the file's own directory when no marker exists.
    static func rootDirectory(
        forFile filePath: String,
        markers: [String],
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String {
        let fileDirectory = (filePath as NSString).deletingLastPathComponent
        for marker in markers {
            var directory = fileDirectory
            while true {
                if fileExists((directory as NSString).appendingPathComponent(marker)) { return directory }
                let parent = (directory as NSString).deletingLastPathComponent
                if parent == directory || parent.isEmpty { break }
                directory = parent
            }
        }
        return fileDirectory
    }

    /// Fills in what only the host knows in the client's `initialize` request.
    static func completingInitialize(_ message: [String: Any], rootDirectory: String, processIdentifier: Int32) -> [String: Any] {
        guard message["method"] as? String == "initialize" else { return message }
        let rootURI = URL(fileURLWithPath: rootDirectory, isDirectory: true).absoluteString
        var params = message["params"] as? [String: Any] ?? [:]
        params["processId"] = Int(processIdentifier)
        params["rootUri"] = rootURI
        params["workspaceFolders"] = [["uri": rootURI, "name": (rootDirectory as NSString).lastPathComponent]]
        var completed = message
        completed["params"] = params
        return completed
    }
}
