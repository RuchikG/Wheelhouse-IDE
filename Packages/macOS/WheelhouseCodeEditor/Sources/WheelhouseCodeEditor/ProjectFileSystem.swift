import Foundation

/// File access for an editor page. With a root (a project editor), everything
/// under it can be listed, read and written, and files elsewhere (a
/// dependency's source, for example) can only be read. Without one (a
/// single-file editor), any file can be read and nothing else is allowed.
struct ProjectFileSystem: Sendable {
    struct Entry: Equatable, Sendable {
        var name: String
        var isDirectory: Bool
    }

    struct File: Equatable, Sendable {
        var content: String
        /// Modification time, used to notice a change made outside the editor.
        var modified: Double
        var isReadOnly: Bool
    }

    /// A line that contains what was searched for.
    struct Match: Equatable, Sendable {
        /// Relative to the root.
        var path: String
        /// Both count from 1; the column is in UTF-16 units, as the editor counts.
        var line: Int
        var column: Int
        /// The line, or the part of a long line around the match.
        var text: String
        /// Where the match is in `text`, in UTF-16 units.
        var matchStart: Int
        var matchLength: Int
    }

    enum Failure: Error, Equatable {
        case outsideProject
        case notText
        case tooLarge
        /// The file changed on disk after the editor read it.
        case changedOnDisk
        /// Something already has the name a new or renamed item asked for.
        case exists
        case unreadable(String)
    }

    static let maximumFileSize = 8 * 1024 * 1024
    /// How many paths `index` returns at most.
    static let maximumIndexedFiles = 20_000
    /// Where a search in files stops: this many lines found, files larger than this left out,
    /// and no longer than this many seconds.
    static let maximumMatches = 1000
    static let maximumSearchedFileSize = 1024 * 1024
    static let maximumSearchSeconds = 10.0
    /// How much of a long line a match carries.
    static let maximumMatchText = 240
    private static let hiddenNames: Set<String> = [".git", ".DS_Store"]
    /// Folders whose contents are not worth finding files in.
    private static let unindexedNames: Set<String> = [".git", "node_modules"]

    let root: String?

    init(root: String?) {
        self.root = root.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
    }

    func contains(_ path: String) -> Bool {
        guard let root else { return false }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return resolved == root || resolved.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    /// Directories first, then files, each sorted by name.
    func list(_ directory: String) throws -> [Entry] {
        guard contains(directory) else { throw Failure.outsideProject }
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: directory, isDirectory: true),
                includingPropertiesForKeys: [.isDirectoryKey]
            )
        } catch {
            throw Failure.unreadable(error.localizedDescription)
        }
        return urls
            .filter { !Self.hiddenNames.contains($0.lastPathComponent) }
            .map { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                return Entry(name: url.lastPathComponent, isDirectory: isDirectory)
            }
            .sorted { left, right in
                if left.isDirectory != right.isDirectory { return left.isDirectory }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
    }

    func read(_ path: String) throws -> File {
        let url = URL(fileURLWithPath: path)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= Self.maximumFileSize else { throw Failure.tooLarge }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw Failure.unreadable(error.localizedDescription)
        }
        guard !data.contains(0), let content = String(data: data, encoding: .utf8) else { throw Failure.notText }
        return File(content: content, modified: Self.modified(path), isReadOnly: !contains(path))
    }

    /// Writes `content` and returns the new modification time.
    /// - Parameter expectedModified: The time `read` reported; `nil` writes
    ///   without checking for a change on disk.
    func write(_ content: String, to path: String, expectedModified: Double?) throws -> Double {
        guard contains(path) else { throw Failure.outsideProject }
        if let expectedModified, FileManager.default.fileExists(atPath: path),
           abs(Self.modified(path) - expectedModified) > 0.001 {
            throw Failure.changedOnDisk
        }
        do {
            try Data(content.utf8).write(to: URL(fileURLWithPath: path))
        } catch {
            throw Failure.unreadable(error.localizedDescription)
        }
        return Self.modified(path)
    }

    func createFile(_ path: String) throws {
        try requireNew(path)
        guard FileManager.default.createFile(atPath: path, contents: Data()) else {
            throw Failure.unreadable("could not create \(path)")
        }
    }

    func createDirectory(_ path: String) throws {
        try requireNew(path)
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
        } catch {
            throw Failure.unreadable(error.localizedDescription)
        }
    }

    /// Renames or moves a file or folder inside the project.
    func move(_ path: String, to destination: String) throws {
        guard contains(path), !isRoot(path) else { throw Failure.outsideProject }
        // A change of letter case names the same item on a case-insensitive volume.
        if path.lowercased() != destination.lowercased() {
            try requireNew(destination)
        } else {
            guard contains(destination) else { throw Failure.outsideProject }
        }
        do {
            try FileManager.default.moveItem(atPath: path, toPath: destination)
        } catch {
            throw Failure.unreadable(error.localizedDescription)
        }
    }

    func trash(_ path: String) throws {
        guard contains(path), !isRoot(path) else { throw Failure.outsideProject }
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
        } catch {
            throw Failure.unreadable(error.localizedDescription)
        }
    }

    /// Every file under the root as a path relative to it, sorted, for finding
    /// a file by name. Stops at `maximumIndexedFiles`.
    func index() throws -> (paths: [String], isComplete: Bool) {
        guard let root else { throw Failure.outsideProject }
        guard let walker = FileManager.default.enumerator(atPath: root) else { throw Failure.unreadable(root) }
        var paths: [String] = []
        var isComplete = true
        for case let path as String in walker {
            let name = (path as NSString).lastPathComponent
            if walker.fileAttributes?[.type] as? FileAttributeType == .typeDirectory {
                if Self.unindexedNames.contains(name) { walker.skipDescendants() }
                continue
            }
            if Self.hiddenNames.contains(name) { continue }
            if paths.count == Self.maximumIndexedFiles {
                isComplete = false
                break
            }
            paths.append(path)
        }
        return (paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, isComplete)
    }

    /// The lines under the root that contain `query`, by path and line. Letter case counts
    /// only when the query has a capital letter. Binary and very large files and the folders
    /// `index` skips are left out.
    func search(_ query: String) throws -> (matches: [Match], isComplete: Bool) {
        guard let root else { throw Failure.outsideProject }
        guard !query.isEmpty else { return ([], true) }
        guard let walker = FileManager.default.enumerator(atPath: root) else { throw Failure.unreadable(root) }
        let options: NSString.CompareOptions = query.contains(where: \.isUppercase) ? [.literal] : [.literal, .caseInsensitive]
        let deadline = Date().addingTimeInterval(Self.maximumSearchSeconds)
        var matches: [Match] = []
        var isComplete = true
        files: for case let path as String in walker {
            try Task.checkCancellation()
            let name = (path as NSString).lastPathComponent
            if walker.fileAttributes?[.type] as? FileAttributeType == .typeDirectory {
                if Self.unindexedNames.contains(name) { walker.skipDescendants() }
                continue
            }
            if Self.hiddenNames.contains(name) { continue }
            if Date() > deadline {
                isComplete = false
                break
            }
            let size = (walker.fileAttributes?[.size] as? NSNumber)?.intValue ?? 0
            guard size > 0, size <= Self.maximumSearchedFileSize,
                  let data = FileManager.default.contents(atPath: root + "/" + path), !data.contains(0),
                  let content = String(data: data, encoding: .utf8),
                  content.range(of: query, options: options) != nil else { continue }
            var number = 0
            // Not `split`: to Swift a carriage return and line feed are one character.
            for line in content.components(separatedBy: "\n") {
                number += 1
                guard let match = Self.match(of: query, in: line, options: options) else { continue }
                if matches.count == Self.maximumMatches {
                    isComplete = false
                    break files
                }
                matches.append(Match(
                    path: path, line: number, column: match.column, text: match.text,
                    matchStart: match.start, matchLength: match.length
                ))
            }
        }
        matches.sort { left, right in
            if left.path != right.path { return left.path.localizedStandardCompare(right.path) == .orderedAscending }
            return left.line < right.line
        }
        return (matches, isComplete)
    }

    /// The first match in a line, with the line cut down around it when it is long.
    private static func match(
        of query: String, in line: String, options: NSString.CompareOptions
    ) -> (column: Int, text: String, start: Int, length: Int)? {
        let text = (line.hasSuffix("\r") ? String(line.dropLast()) : line) as NSString
        let found = text.range(of: query, options: options)
        guard found.location != NSNotFound else { return nil }
        guard text.length > maximumMatchText else {
            return (found.location + 1, text as String, found.location, found.length)
        }
        let from = max(0, min(found.location - maximumMatchText / 4, text.length - maximumMatchText))
        let shown = text.rangeOfComposedCharacterSequences(for: NSRange(location: from, length: maximumMatchText))
        return (
            found.location + 1, text.substring(with: shown),
            found.location - shown.location, min(found.length, NSMaxRange(shown) - found.location)
        )
    }

    private func isRoot(_ path: String) -> Bool {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path == root
    }

    /// `path` must be inside the project and not exist yet.
    private func requireNew(_ path: String) throws {
        guard contains((path as NSString).deletingLastPathComponent) else { throw Failure.outsideProject }
        guard !FileManager.default.fileExists(atPath: path) else { throw Failure.exists }
    }

    private static func modified(_ path: String) -> Double {
        let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        return date?.timeIntervalSince1970 ?? 0
    }
}
