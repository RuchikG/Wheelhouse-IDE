import AppKit
import Foundation
public import WebKit

/// Owns the web editor's `WKWebView` and the message bridge to it.
@MainActor
public final class CodeEditorCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private static let messageHandlerName = "cmuxCodeEditor"

    private(set) var webView: CodeEditorWebView?
    private var isReady = false
    private var sync = CodeEditorDocumentSync()
    private var document: CodeEditorDocument?
    private var project: CodeEditorProject?
    private var sentProject: CodeEditorProject?
    private var options: CodeEditorOptions?
    private var theme: CodeEditorTheme?
    private var sentOptions: CodeEditorOptions?
    private var sentTheme: CodeEditorTheme?

    /// Forwards uncaught page errors, failed resource loads and rejected
    /// promises to the host, where they are logged.
    private static let errorReportingScript = """
    (() => {
      const report = (message) => {
        try {
          window.webkit.messageHandlers.\(messageHandlerName).postMessage({ type: "error", message: String(message) });
        } catch (_) {}
      };
      window.addEventListener("error", (event) => {
        const target = event.target;
        if (target && target !== window && (target.src || target.href)) {
          report("failed to load " + (target.src || target.href));
        } else {
          report((event.message || "error") + " at " + (event.filename || "?") + ":" + (event.lineno || 0));
        }
      }, true);
      window.addEventListener("unhandledrejection", (event) => {
        report("unhandled rejection: " + (event.reason && (event.reason.stack || event.reason.message) || event.reason));
      });
    })();
    """

    var onContentChange: (@MainActor (String) -> Void)?
    var onSave: (@MainActor (String) -> Void)?
    var onPointerDown: (@MainActor () -> Void)?
    var onOpenFile: (@MainActor (String) -> Void)?
    /// Whether any file open in a project has unsaved edits.
    var onProjectDirtyChange: (@MainActor (Bool) -> Void)?

    /// Running language servers by file extension.
    private var languageServers: [String: LanguageServerProcess] = [:]
    private var languageServerRoots: [String: String] = [:]
    private var startingLanguageServers = Set<String>()
    /// Bumped when the page restarts, so work started for the old page is dropped.
    private var pageGeneration = 0

    private static let liveCoordinators = NSHashTable<CodeEditorCoordinator>.weakObjects()
    /// Positions to show once the editor for a path has its document.
    private static var pendingReveals: [String: (line: Int, column: Int)] = [:]

    func ensureWebView(assetDirectory: URL) -> CodeEditorWebView {
        if let webView { return webView }

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(
            CodeEditorAssetSchemeHandler(store: CodeEditorAssetStore(rootDirectory: assetDirectory)),
            forURLScheme: CodeEditorAssetSchemeHandler.scheme
        )
        configuration.userContentController.add(self, name: Self.messageHandlerName)
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.errorReportingScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        let webView = CodeEditorWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.navigationDelegate = self
#if DEBUG
        webView.isInspectable = true
#endif
        webView.onPointerDown = { [weak self] in self?.onPointerDown?() }
        webView.onBecomeFirstResponder = { [weak self] in self?.send(["type": "focus"]) }
        self.webView = webView
        Self.liveCoordinators.add(self)
        webView.load(URLRequest(url: CodeEditorAssetSchemeHandler.pageURL))
        return webView
    }

    func update(document: CodeEditorDocument, options: CodeEditorOptions, theme: CodeEditorTheme) {
        self.document = document
        self.options = options
        self.theme = theme
        flush()
    }

    func update(project: CodeEditorProject, options: CodeEditorOptions, theme: CodeEditorTheme) {
        self.project = project
        self.options = options
        self.theme = theme
        flush()
    }

    func close() {
        guard let webView else { return }
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageHandlerName)
        webView.navigationDelegate = nil
        webView.stopLoading()
        webView.removeFromSuperview()
        self.webView = nil
        isReady = false
        stopLanguageServers()
        Self.liveCoordinators.remove(self)
    }

    private func flush() {
        guard isReady else { return }
        if let theme, theme != sentTheme {
            sentTheme = theme
            send(["type": "theme", "theme": Self.jsonObject(theme)])
        }
        if let options, options != sentOptions {
            sentOptions = options
            send(["type": "options", "options": Self.jsonObject(options)])
        }
        if let project, project != sentProject {
            sentProject = project
            send([
                "type": "project",
                "root": project.rootPath,
                "name": (project.rootPath as NSString).lastPathComponent,
            ])
        }
        if let document, let sequence = sync.outgoingSequence(for: document) {
            send([
                "type": "document",
                "path": document.path,
                "content": document.content,
                "sequence": sequence,
                "readOnly": document.isReadOnly,
            ])
        }
        if let document, let position = Self.pendingReveals.removeValue(forKey: Self.revealKey(document.path)) {
            send(["type": "reveal", "line": position.line, "column": position.column])
        }
    }

    /// Shows a position in the editor for `path`: now when that editor is
    /// loaded, otherwise as soon as one opens the file.
    static func reveal(path: String, line: Int, column: Int) {
        let key = revealKey(path)
        let loaded = liveCoordinators.allObjects.first { coordinator in
            coordinator.isReady && coordinator.document.map { revealKey($0.path) } == key
        }
        if let loaded {
            loaded.send(["type": "reveal", "line": line, "column": column])
        } else {
            pendingReveals[key] = (line, column)
        }
    }

    private static func revealKey(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private func send(_ message: [String: Any]) {
        guard isReady, let webView,
              let data = try? JSONSerialization.data(withJSONObject: message),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.cmuxCodeEditor?.receive(\(json));") { _, error in
            if let error {
                CodeEditorLog.bridge.error("message to page failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func jsonObject(_ value: some Encodable) -> Any {
        guard let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) else { return [:] as [String: Any] }
        return object
    }

    private func pageDidRestart() {
        isReady = false
        sentOptions = nil
        sentTheme = nil
        sentProject = nil
        sync.reset()
        stopLanguageServers()
    }

    // MARK: Project files

    /// Answers a file request from the project page. File access runs off the
    /// main thread; the reply carries the request's `id`.
    private func handleFileRequest(_ body: [String: Any]) {
        guard let project, let id = body["id"] as? Int, let operation = body["op"] as? String,
              let path = body["path"] as? String, path.hasPrefix("/") else { return }
        let files = ProjectFileSystem(root: project.rootPath)
        let content = body["content"] as? String
        let expectedModified = body["modified"] as? Double
        let generation = pageGeneration
        Task { [weak self] in
            let reply = await Task.detached { () -> FileReply in
                Self.perform(operation, path: path, content: content, expectedModified: expectedModified, in: files)
            }.value
            guard let self, self.pageGeneration == generation else { return }
            if case .changedOnDisk = reply, let content {
                self.resolveChangedOnDisk(id: id, path: path, content: content, files: files)
            } else {
                self.send(reply.message(id: id))
            }
        }
    }

    private enum FileReply: Sendable {
        case entries([ProjectFileSystem.Entry])
        case file(ProjectFileSystem.File)
        case written(Double)
        case changedOnDisk
        case failed(String)

        func message(id: Int) -> [String: Any] {
            var message: [String: Any] = ["type": "fsResult", "id": id, "ok": true]
            switch self {
            case .entries(let entries):
                message["entries"] = entries.map { ["name": $0.name, "isDirectory": $0.isDirectory] }
            case .file(let file):
                message["content"] = file.content
                message["modified"] = file.modified
                message["readOnly"] = file.isReadOnly
            case .written(let modified):
                message["modified"] = modified
            case .changedOnDisk:
                message["ok"] = false
                message["error"] = "changedOnDisk"
            case .failed(let reason):
                message["ok"] = false
                message["error"] = reason
            }
            return message
        }
    }

    private nonisolated static func perform(
        _ operation: String,
        path: String,
        content: String?,
        expectedModified: Double?,
        in files: ProjectFileSystem
    ) -> FileReply {
        do {
            switch operation {
            case "list":
                return .entries(try files.list(path))
            case "read":
                return .file(try files.read(path))
            case "write":
                guard let content else { return .failed("unreadable") }
                return .written(try files.write(content, to: path, expectedModified: expectedModified))
            default:
                return .failed("unsupported")
            }
        } catch ProjectFileSystem.Failure.changedOnDisk {
            return .changedOnDisk
        } catch ProjectFileSystem.Failure.notText {
            return .failed("notText")
        } catch ProjectFileSystem.Failure.tooLarge {
            return .failed("tooLarge")
        } catch ProjectFileSystem.Failure.outsideProject {
            return .failed("outsideProject")
        } catch {
            return .failed("unreadable")
        }
    }

    /// A save found the file changed by something else since it was read.
    private func resolveChangedOnDisk(id: Int, path: String, content: String, files: ProjectFileSystem) {
        let alert = NSAlert()
        alert.messageText = String(
            localized: "wheelhouse.project.changedOnDisk.title",
            defaultValue: "“\((path as NSString).lastPathComponent)” changed on disk"
        )
        alert.informativeText = String(
            localized: "wheelhouse.project.changedOnDisk.message",
            defaultValue: "Something else modified this file after it was opened here. Saving replaces those changes."
        )
        alert.addButton(withTitle: String(localized: "wheelhouse.project.changedOnDisk.cancel", defaultValue: "Cancel"))
        alert.addButton(withTitle: String(localized: "wheelhouse.project.changedOnDisk.overwrite", defaultValue: "Overwrite"))
        guard alert.runModal() == .alertSecondButtonReturn else {
            send(FileReply.changedOnDisk.message(id: id))
            return
        }
        let reply = Self.perform("write", path: path, content: content, expectedModified: nil, in: files)
        send(reply.message(id: id))
    }

    /// Asks what to do with unsaved edits in a file the page is about to close.
    private func confirmClose(_ body: [String: Any]) {
        guard let id = body["id"] as? Int, let name = body["name"] as? String else { return }
        let alert = NSAlert()
        alert.messageText = String(
            localized: "wheelhouse.project.unsaved.title",
            defaultValue: "Save changes to “\(name)”?"
        )
        alert.informativeText = String(
            localized: "wheelhouse.project.unsaved.message",
            defaultValue: "Your changes are lost if you don’t save them."
        )
        alert.addButton(withTitle: String(localized: "wheelhouse.project.unsaved.save", defaultValue: "Save"))
        alert.addButton(withTitle: String(localized: "wheelhouse.project.unsaved.cancel", defaultValue: "Cancel"))
        alert.addButton(withTitle: String(localized: "wheelhouse.project.unsaved.discard", defaultValue: "Don’t Save"))
        let choice: String
        switch alert.runModal() {
        case .alertFirstButtonReturn: choice = "save"
        case .alertThirdButtonReturn: choice = "discard"
        default: choice = "cancel"
        }
        send(["type": "confirmResult", "id": id, "choice": choice])
    }

    // MARK: Language servers

    private func stopLanguageServers() {
        pageGeneration += 1
        languageServers.values.forEach { $0.stop() }
        languageServers.removeAll()
        languageServerRoots.removeAll()
        startingLanguageServers.removeAll()
    }

    private func sendLanguageServerState(_ server: String, _ state: String) {
        send(["type": "lspState", "server": server, "state": state])
    }

    /// Starts the server for files with extension `server`, as asked by the page.
    private func startLanguageServer(_ server: String) {
        guard languageServers[server] == nil, !startingLanguageServers.contains(server) else { return }
        guard let path = document?.path ?? project?.rootPath,
              let definition = LanguageServerRegistry.definition(
                  forFileExtension: server,
                  overrides: UserDefaults.standard.dictionary(forKey: LanguageServerRegistry.defaultsKey)
              ) else {
            sendLanguageServerState(server, "unavailable")
            return
        }
        startingLanguageServers.insert(server)
        let generation = pageGeneration
        Task { [weak self] in
            let searchPath = await LanguageServerEnvironment.shared.searchPath()
            guard let self, self.pageGeneration == generation else { return }
            self.startingLanguageServers.remove(server)
            guard let executable = LanguageServerEnvironment.executable(named: definition.command[0], searchPath: searchPath) else {
                CodeEditorLog.languageServer.notice("no \(definition.command[0], privacy: .public) on PATH; language features are off")
                self.sendLanguageServerState(server, "unavailable")
                return
            }
            // A project's server is rooted at the project folder, a single file's at its module.
            let root = self.project?.rootPath
                ?? LanguageServerRegistry.rootDirectory(forFile: path, markers: definition.rootMarkers)
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = searchPath
            let process = LanguageServerProcess(
                executable: executable,
                arguments: Array(definition.command.dropFirst()),
                environment: environment,
                directory: URL(fileURLWithPath: root, isDirectory: true),
                onMessage: { [weak self] body in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self?.deliver(body, from: server, generation: generation) }
                    }
                },
                onExit: { [weak self] in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self?.languageServerDidExit(server, generation: generation) }
                    }
                }
            )
            do {
                try process.start()
            } catch {
                CodeEditorLog.languageServer.error("could not start \(executable.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                self.sendLanguageServerState(server, "unavailable")
                return
            }
            CodeEditorLog.languageServer.notice("started \(executable.lastPathComponent, privacy: .public) for \(root, privacy: .public)")
            self.languageServers[server] = process
            self.languageServerRoots[server] = root
            self.sendLanguageServerState(server, "open")
        }
    }

    private func forwardToLanguageServer(_ server: String, _ message: [String: Any]) {
        guard let process = languageServers[server], let root = languageServerRoots[server] else { return }
        let completed = LanguageServerRegistry.completingInitialize(
            message, rootDirectory: root, processIdentifier: ProcessInfo.processInfo.processIdentifier
        )
        guard let body = try? JSONSerialization.data(withJSONObject: completed) else { return }
        process.send(body)
    }

    private func deliver(_ body: Data, from server: String, generation: Int) {
        guard generation == pageGeneration, isReady, let webView,
              let json = String(data: body, encoding: .utf8),
              let serverName = try? JSONSerialization.data(withJSONObject: [server]),
              let serverJSON = String(data: serverName, encoding: .utf8) else { return }
        // The body is already JSON text; passing it through avoids a decode and encode per message.
        webView.evaluateJavaScript(
            "window.cmuxCodeEditor?.receive({type:\"lsp\",server:\(serverJSON)[0],message:\(json)});"
        ) { _, error in
            if let error {
                CodeEditorLog.languageServer.error("message to page failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func languageServerDidExit(_ server: String, generation: Int) {
        guard generation == pageGeneration, languageServers.removeValue(forKey: server) != nil else { return }
        languageServerRoots.removeValue(forKey: server)
        CodeEditorLog.languageServer.notice("language server for .\(server, privacy: .public) exited")
        sendLanguageServerState(server, "closed")
    }

    // MARK: WKScriptMessageHandler

    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            CodeEditorLog.bridge.notice("editor ready")
            pageDidRestart()
            isReady = true
            flush()
        case "error":
            CodeEditorLog.bridge.error("page error: \(body["message"] as? String ?? "", privacy: .public)")
        case "change", "save":
            guard let content = body["content"] as? String,
                  let sequence = body["sequence"] as? Int,
                  sync.acceptIncoming(content: content, sequence: sequence) else { return }
            if type == "save" {
                onSave?(content)
            } else {
                onContentChange?(content)
            }
        case "lspStart":
            if let server = body["server"] as? String {
                startLanguageServer(server.lowercased())
            }
        case "lsp":
            if let server = body["server"] as? String, let json = body["json"] as? String,
               let message = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] {
                forwardToLanguageServer(server, message)
            }
        case "fs":
            handleFileRequest(body)
        case "confirmClose":
            confirmClose(body)
        case "projectDirty":
            onProjectDirtyChange?(body["dirty"] as? Bool ?? false)
        case "openFile":
            guard let path = body["path"] as? String, path.hasPrefix("/") else { return }
            Self.reveal(path: path, line: body["line"] as? Int ?? 1, column: body["column"] as? Int ?? 1)
            onOpenFile?(path)
        default:
            break
        }
    }

    // MARK: WKNavigationDelegate

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        navigationAction.request.url?.scheme == CodeEditorAssetSchemeHandler.scheme ? .allow : .cancel
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        CodeEditorLog.bridge.error("page failed to load: \(error.localizedDescription, privacy: .public)")
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        CodeEditorLog.bridge.error("page navigation failed: \(error.localizedDescription, privacy: .public)")
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        CodeEditorLog.bridge.error("web content process terminated; reloading")
        pageDidRestart()
        webView.load(URLRequest(url: CodeEditorAssetSchemeHandler.pageURL))
    }
}
