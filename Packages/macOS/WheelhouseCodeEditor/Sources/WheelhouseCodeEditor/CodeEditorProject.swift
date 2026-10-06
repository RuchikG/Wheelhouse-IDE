/// A folder shown in a project editor: a file tree with the files opened from it.
public struct CodeEditorProject: Equatable, Sendable {
    /// Absolute path of the folder.
    public var rootPath: String

    public init(rootPath: String) {
        self.rootPath = rootPath
    }
}
