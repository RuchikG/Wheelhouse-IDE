import Foundation

/// The files a project editor had open, remembered per folder so the tab shows
/// them again after a restart.
struct ProjectEditorSession: Equatable, Sendable {
    static let defaultsKey = "wheelhouse.projectEditor.sessions"

    /// Absolute paths, in the order of the strip.
    var openFiles: [String] = []
    var activeFile: String?

    /// - Parameter host: The remote host that holds the folder; `nil` for this Mac.
    static func load(root: String, host: String? = nil, from defaults: UserDefaults = .standard) -> ProjectEditorSession {
        guard let stored = defaults.dictionary(forKey: defaultsKey)?[key(root, host)] as? [String: Any] else {
            return ProjectEditorSession()
        }
        return ProjectEditorSession(
            openFiles: stored["open"] as? [String] ?? [],
            activeFile: stored["active"] as? String
        )
    }

    func save(root: String, host: String? = nil, to defaults: UserDefaults = .standard) {
        var sessions = defaults.dictionary(forKey: Self.defaultsKey) ?? [:]
        if openFiles.isEmpty {
            sessions.removeValue(forKey: Self.key(root, host))
        } else {
            var stored: [String: Any] = ["open": openFiles]
            stored["active"] = activeFile
            sessions[Self.key(root, host)] = stored
        }
        defaults.set(sessions, forKey: Self.defaultsKey)
    }

    private static func key(_ root: String, _ host: String?) -> String {
        if let host { return "\(host):\(root)" }
        return URL(fileURLWithPath: root).resolvingSymlinksInPath().path
    }
}
