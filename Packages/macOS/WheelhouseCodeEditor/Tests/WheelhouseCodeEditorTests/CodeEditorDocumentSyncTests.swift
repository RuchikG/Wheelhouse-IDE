import Testing
@testable import WheelhouseCodeEditor

@Suite struct CodeEditorDocumentSyncTests {
    private func document(_ content: String, revision: Int, path: String = "/tmp/a.go") -> CodeEditorDocument {
        CodeEditorDocument(path: path, content: content, contentRevision: revision)
    }

    @Test func sendsFirstDocumentOnce() {
        var sync = CodeEditorDocumentSync()
        let first = sync.outgoingSequence(for: document("a", revision: 1))
        let repeated = sync.outgoingSequence(for: document("a", revision: 1))
        #expect(first == 1)
        #expect(repeated == nil)
    }

    @Test func doesNotEchoAnEditBackToTheEditor() {
        var sync = CodeEditorDocumentSync()
        _ = sync.outgoingSequence(for: document("a", revision: 1))
        let accepted = sync.acceptIncoming(content: "ab", sequence: 1)
        let echo = sync.outgoingSequence(for: document("ab", revision: 2))
        #expect(accepted)
        #expect(echo == nil)
    }

    @Test func sendsOwnerReplacementAndDropsStaleEdit() {
        var sync = CodeEditorDocumentSync()
        _ = sync.outgoingSequence(for: document("a", revision: 1))
        _ = sync.acceptIncoming(content: "ab", sequence: 1)
        _ = sync.outgoingSequence(for: document("ab", revision: 2))
        let reverted = sync.outgoingSequence(for: document("a", revision: 3))
        let stale = sync.acceptIncoming(content: "abc", sequence: 1)
        let current = sync.acceptIncoming(content: "ax", sequence: 2)
        #expect(reverted == 2)
        #expect(!stale)
        #expect(current)
    }

    @Test func resendsAfterPathOrReadOnlyChange() {
        var sync = CodeEditorDocumentSync()
        _ = sync.outgoingSequence(for: document("a", revision: 1))
        let moved = sync.outgoingSequence(for: document("a", revision: 1, path: "/tmp/b.go"))
        var readOnlyDocument = document("a", revision: 1, path: "/tmp/b.go")
        readOnlyDocument.isReadOnly = true
        let readOnly = sync.outgoingSequence(for: readOnlyDocument)
        #expect(moved == 2)
        #expect(readOnly == 3)
    }

    @Test func resendsAfterReset() {
        var sync = CodeEditorDocumentSync()
        _ = sync.outgoingSequence(for: document("a", revision: 1))
        sync.reset()
        let resent = sync.outgoingSequence(for: document("a", revision: 1))
        #expect(resent == 2)
    }
}
