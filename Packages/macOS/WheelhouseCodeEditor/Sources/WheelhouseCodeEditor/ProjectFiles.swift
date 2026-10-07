import Foundation

/// The file operations a project editor needs, on whichever machine holds the
/// project. Failures are thrown as `ProjectFileSystem.Failure`.
protocol ProjectFiles: Sendable {
    func list(_ directory: String) async throws -> [ProjectFileSystem.Entry]
    func read(_ path: String) async throws -> ProjectFileSystem.File
    /// Writes `content` and returns the new modification time.
    func write(_ content: String, to path: String, expectedModified: Double?) async throws -> Double
    func createFile(_ path: String) async throws
    func createDirectory(_ path: String) async throws
    func move(_ path: String, to destination: String) async throws
    /// Removes a file or folder: to the Trash where there is one, for good otherwise.
    func trash(_ path: String) async throws
    func index() async throws -> (paths: [String], isComplete: Bool)
    /// The lines of the project's files that contain `query`.
    func search(_ query: String) async throws -> (matches: [ProjectFileSystem.Match], isComplete: Bool)
    /// Ends whatever the implementation keeps running.
    func close()
}

extension ProjectFileSystem: ProjectFiles {
    func close() {}
}
