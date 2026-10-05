import Foundation

/// Reads the bundled web editor's files from one directory.
struct CodeEditorAssetStore: Sendable {
    struct Asset: Equatable, Sendable {
        var data: Data
        var mimeType: String
    }

    private let rootDirectory: URL

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
    }

    /// Resolves a request URL's path to file contents, refusing paths outside
    /// the root. A missing `.js`/`.mjs` falls back to its build-time `.deflate`
    /// sibling.
    func asset(for url: URL) -> Asset? {
        let relativePath = String(url.path.drop(while: { $0 == "/" }))
        guard !relativePath.isEmpty else { return nil }
        let fileURL = rootDirectory.appendingPathComponent(relativePath, isDirectory: false)
            .standardizedFileURL.resolvingSymlinksInPath()
        guard fileURL.path.hasPrefix(rootDirectory.path + "/") else { return nil }

        let mimeType = Self.mimeType(forPathExtension: fileURL.pathExtension)
        if let data = try? Data(contentsOf: fileURL) {
            return Asset(data: data, mimeType: mimeType)
        }
        guard let compressed = try? Data(contentsOf: fileURL.appendingPathExtension("deflate")),
              let data = CodeEditorAssetInflater.inflate(compressed) else {
            return nil
        }
        return Asset(data: data, mimeType: mimeType)
    }

    static func mimeType(forPathExtension pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html": "text/html; charset=utf-8"
        case "js", "mjs": "text/javascript; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "json": "application/json"
        case "ttf": "font/ttf"
        case "svg": "image/svg+xml"
        default: "application/octet-stream"
        }
    }
}
