import Foundation
import Testing
@testable import WheelhouseCodeEditor

@Suite struct CodeEditorAssetStoreTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("code-editor-assets-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("chunks"), withIntermediateDirectories: true
        )
        return root
    }

    @Test func servesFilesUnderTheRoot() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("<html>".utf8).write(to: root.appendingPathComponent("code-editor.html"))

        let asset = CodeEditorAssetStore(rootDirectory: root).asset(for: URL(string: "cmux-code-editor://app/code-editor.html")!)
        #expect(asset?.data == Data("<html>".utf8))
        #expect(asset?.mimeType == "text/html; charset=utf-8")
    }

    @Test func refusesPathsOutsideTheRoot() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).mjs")
        try Data("x".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }

        let url = URL(string: "cmux-code-editor://app/chunks/../../\(outside.lastPathComponent)")!
        #expect(CodeEditorAssetStore(rootDirectory: root).asset(for: url) == nil)
    }

    @Test func inflatesDeflatedScripts() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // zlib.compress(b"export {};", 9)
        let deflated = Data([
            0x78, 0xDA, 0x4B, 0xAD, 0x28, 0xC8, 0x2F, 0x2A, 0x51, 0xA8, 0xAE, 0xB5,
            0x06, 0x00, 0x16, 0xD3, 0x03, 0xF6,
        ])
        try deflated.write(to: root.appendingPathComponent("chunks/a.mjs.deflate"))

        let url = URL(string: "cmux-code-editor://app/chunks/a.mjs")!
        let asset = CodeEditorAssetStore(rootDirectory: root).asset(for: url)
        #expect(asset?.data == Data("export {};".utf8))
        #expect(asset?.mimeType == "text/javascript; charset=utf-8")
    }
}
