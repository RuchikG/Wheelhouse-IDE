import Foundation

/// A running language server that speaks JSON-RPC over its standard streams.
final class LanguageServerProcess: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let writeQueue = DispatchQueue(label: "wheelhouse.language-server.write")
    private let lock = NSLock()
    private var framer = LanguageServerMessageFramer()

    var processIdentifier: Int32 { process.processIdentifier }

    /// - Parameters:
    ///   - onMessage: One JSON-RPC message body from the server; called off the main thread.
    ///   - onExit: The server process ended; called off the main thread.
    init(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        directory: URL,
        onMessage: @escaping @Sendable (Data) -> Void,
        onExit: @escaping @Sendable () -> Void
    ) {
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = directory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else {
                handle.readabilityHandler = nil
                return
            }
            self.lock.lock()
            let messages = self.framer.append(data)
            self.lock.unlock()
            messages.forEach(onMessage)
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            CodeEditorLog.languageServer.debug("server stderr: \(String(decoding: data, as: UTF8.self), privacy: .public)")
        }
        process.terminationHandler = { _ in onExit() }
    }

    func start() throws {
        try process.run()
    }

    /// Sends one JSON-RPC message body to the server.
    func send(_ body: Data) {
        let handle = input.fileHandleForWriting
        writeQueue.async {
            do {
                try handle.write(contentsOf: LanguageServerMessageFramer.frame(body))
            } catch {
                CodeEditorLog.languageServer.error("write to server failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func stop() {
        let handle = input.fileHandleForWriting
        writeQueue.async { try? handle.close() }
        if process.isRunning {
            process.terminate()
        }
    }
}
