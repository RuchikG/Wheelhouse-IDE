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
