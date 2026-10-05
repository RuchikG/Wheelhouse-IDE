/// The file shown in a ``CodeEditorView``.
public struct CodeEditorDocument: Equatable, Sendable {
    /// Absolute path; selects the syntax grammar and identifies the model.
    public var path: String
    public var content: String
    /// Changes whenever the owner replaces `content`, so the editor can skip
    /// comparing large strings on unrelated view updates.
    public var contentRevision: Int
    public var isReadOnly: Bool

    public init(path: String, content: String, contentRevision: Int, isReadOnly: Bool = false) {
        self.path = path
        self.content = content
        self.contentRevision = contentRevision
        self.isReadOnly = isReadOnly
    }
}
