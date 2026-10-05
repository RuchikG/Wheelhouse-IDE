/// Tracks which content the web editor holds, so an edit reported by the web
/// editor is not pushed back to it and a stale edit cannot overwrite a newer
/// document from the owner.
struct CodeEditorDocumentSync {
    /// Identifies the last document sent; the web editor echoes it on every edit.
    private(set) var sequence = 0
    private var syncedPath: String?
    private var syncedContent: String?
    private var syncedReadOnly: Bool?
    private var seenRevision: Int?

    /// Returns the sequence to send `document` under, or `nil` when the web
    /// editor already shows it.
    mutating func outgoingSequence(for document: CodeEditorDocument) -> Int? {
        let revisionChanged = seenRevision != document.contentRevision
        seenRevision = document.contentRevision
        let needsSend = syncedPath != document.path
            || syncedReadOnly != document.isReadOnly
            || (revisionChanged && syncedContent != document.content)
        guard needsSend else { return nil }
        syncedPath = document.path
        syncedContent = document.content
        syncedReadOnly = document.isReadOnly
        sequence += 1
        return sequence
    }

    /// Records an edit from the web editor. Returns `false` for an edit made
    /// against a document that has since been replaced.
    mutating func acceptIncoming(content: String, sequence: Int) -> Bool {
        guard sequence == self.sequence else { return false }
        syncedContent = content
        return true
    }

    /// Forgets what the web editor holds, after its page reloads.
    mutating func reset() {
        syncedPath = nil
        syncedContent = nil
        syncedReadOnly = nil
        seenRevision = nil
    }
}
