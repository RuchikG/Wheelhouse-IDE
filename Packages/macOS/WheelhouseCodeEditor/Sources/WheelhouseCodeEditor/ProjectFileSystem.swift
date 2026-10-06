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
        case unreadable(String)
    }

    static let maximumFileSize = 8 * 1024 * 1024
    private static let hiddenNames: Set<String> = [".git", ".DS_Store"]

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

    private static func modified(_ path: String) -> Double {
        let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        return date?.timeIntervalSince1970 ?? 0
    }
}
