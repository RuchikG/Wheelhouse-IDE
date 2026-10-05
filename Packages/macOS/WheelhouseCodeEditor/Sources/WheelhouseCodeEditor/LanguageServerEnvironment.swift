import Foundation

/// Finds language server executables the way the user's terminal would. An app
/// started from the Dock gets a minimal `PATH`, so the login shell is asked for its own.
actor LanguageServerEnvironment {
    static let shared = LanguageServerEnvironment()

    private static let marker = "__WHEELHOUSE_PATH__"
    private var resolvedPath: String?

    /// The login shell's `PATH`, read once; the process `PATH` when the shell does not answer.
    func searchPath() async -> String {
        if let resolvedPath { return resolvedPath }
        let environment = ProcessInfo.processInfo.environment
        let shell = environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        let shellPath = await Self.readPath(shell: shell)
        let home = NSHomeDirectory()
        let path = Self.joined([
            shellPath,
            environment["PATH"],
            "\(home)/go/bin:\(home)/.cargo/bin:\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/local/go/bin",
        ])
        resolvedPath = path
        return path
    }

    static func joined(_ paths: [String?]) -> String {
        var seen = Set<String>()
        return paths
            .compactMap { $0 }
            .flatMap { $0.split(separator: ":").map(String.init) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")
    }

    static func executable(named name: String, searchPath: String) -> URL? {
        if name.contains("/") {
            let expanded = (name as NSString).expandingTildeInPath
            return FileManager.default.isExecutableFile(atPath: expanded) ? URL(fileURLWithPath: expanded) : nil
        }
        for directory in searchPath.split(separator: ":") {
            let candidate = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return URL(fileURLWithPath: candidate) }
        }
        return nil
    }

    /// The text between the markers in a shell's output; rc files may print around it.
    static func path(inShellOutput output: String) -> String? {
        let parts = output.components(separatedBy: marker)
        guard parts.count >= 3, !parts[1].isEmpty else { return nil }
        return parts[1]
    }

    private static func readPath(shell: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let output = Pipe()
                process.executableURL = URL(fileURLWithPath: shell)
                process.arguments = ["-l", "-i", "-c", "printf '%s%s%s' '\(marker)' \"$PATH\" '\(marker)'"]
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: watchdog)
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()
                continuation.resume(returning: path(inShellOutput: String(decoding: data, as: UTF8.self)))
            }
        }
    }
}
