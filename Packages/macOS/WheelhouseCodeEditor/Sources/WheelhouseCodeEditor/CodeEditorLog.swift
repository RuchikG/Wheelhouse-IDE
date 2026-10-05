import OSLog

/// Read with `log show --last 5m --predicate 'subsystem == "wheelhouse.code-editor"'`.
enum CodeEditorLog {
    static let bridge = Logger(subsystem: "wheelhouse.code-editor", category: "bridge")
    static let assets = Logger(subsystem: "wheelhouse.code-editor", category: "assets")
    static let languageServer = Logger(subsystem: "wheelhouse.code-editor", category: "language-server")
}
