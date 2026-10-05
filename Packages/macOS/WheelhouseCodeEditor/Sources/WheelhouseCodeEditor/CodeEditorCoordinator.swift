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
        webView.load(URLRequest(url: CodeEditorAssetSchemeHandler.pageURL))
        return webView
    }

    func update(document: CodeEditorDocument, options: CodeEditorOptions, theme: CodeEditorTheme) {
        self.document = document
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
        if let document, let sequence = sync.outgoingSequence(for: document) {
            send([
                "type": "document",
                "path": document.path,
                "content": document.content,
                "sequence": sequence,
                "readOnly": document.isReadOnly,
            ])
        }
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
        sync.reset()
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
