import Foundation
import Testing
@testable import WheelhouseCodeEditor

/// Files that exercise a search in files, shared with the remote helper's test.
enum ProjectSearchFixture {
    static let queries = ["needle", "Needle", "héllo", "main", "nothing here", "tail"]

    static func write(into root: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: root.appendingPathComponent("pkg/deep"), withIntermediateDirectories: true)
        try manager.createDirectory(at: root.appendingPathComponent("node_modules/dep"), withIntermediateDirectories: true)
        try manager.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try Data("first\n  a needle here, and a needle there\nNeedle again\r\nlast\n".utf8)
            .write(to: root.appendingPathComponent("pkg/a.txt"))
        try Data("// 😀 héllo needle\n".utf8).write(to: root.appendingPathComponent("pkg/deep/b.go"))
        try Data("needle in a dependency\n".utf8).write(to: root.appendingPathComponent("node_modules/dep/index.js"))
        try Data("needle in git\n".utf8).write(to: root.appendingPathComponent(".git/config"))
        try Data([0x6E, 0x65, 0x65, 0x64, 0x6C, 0x65, 0x00, 0x01]).write(to: root.appendingPathComponent("pkg/binary.bin"))
        try Data((String(repeating: "x", count: 400) + " tail of a long line " + String(repeating: "y", count: 400) + "\n").utf8)
            .write(to: root.appendingPathComponent("pkg/long.txt"))
    }
}

@Suite struct ProjectSearchTests {
    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("search-project-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try ProjectSearchFixture.write(into: root)
        return root
    }

    @Test func findsLinesByPathAndLineIgnoringCase() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let found = try ProjectFileSystem(root: root.path).search("needle")
        #expect(found.isComplete)
        #expect(found.matches.map { "\($0.path):\($0.line):\($0.column)" } == [
            "pkg/a.txt:2:5", "pkg/a.txt:3:1", "pkg/deep/b.go:1:13",
        ])
        #expect(found.matches[0].text == "  a needle here, and a needle there")
        #expect(found.matches[0].matchStart == 4)
        #expect(found.matches[0].matchLength == 6)
        // A line that ended in a carriage return comes without it.
        #expect(found.matches[1].text == "Needle again")
    }

    @Test func aCapitalLetterMakesCaseCount() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let found = try ProjectFileSystem(root: root.path).search("Needle")
        #expect(found.matches.map { "\($0.path):\($0.line)" } == ["pkg/a.txt:3"])
    }

    @Test func aLongLineIsCutDownAroundTheMatch() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let match = try #require(try ProjectFileSystem(root: root.path).search("tail").matches.first)
        #expect(match.column == 402)
        #expect((match.text as NSString).length == ProjectFileSystem.maximumMatchText)
        #expect((match.text as NSString).substring(with: NSRange(location: match.matchStart, length: match.matchLength)) == "tail")
    }

    @Test func anEmptyQueryFindsNothingAndASingleFileEditorCannotSearch() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try ProjectFileSystem(root: root.path).search("").matches.isEmpty)
        #expect(throws: ProjectFileSystem.Failure.outsideProject) { try ProjectFileSystem(root: nil).search("needle") }
    }
}
