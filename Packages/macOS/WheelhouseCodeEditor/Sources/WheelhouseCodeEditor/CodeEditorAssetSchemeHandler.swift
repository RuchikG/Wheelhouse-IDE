import Foundation
import WebKit

/// Serves the bundled web editor under a private URL scheme, so the page has a
/// real origin for module workers and stylesheet loads.
final class CodeEditorAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "cmux-code-editor"
    static let pageURL = URL(string: "\(scheme)://app/code-editor.html")!

    private let store: CodeEditorAssetStore

    init(store: CodeEditorAssetStore) {
        self.store = store
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, let asset = store.asset(for: url) else {
            CodeEditorLog.assets.error(
                "missing asset \(urlSchemeTask.request.url?.path ?? "", privacy: .public)"
            )
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": asset.mimeType,
                "Content-Length": String(asset.data.count),
                "Cache-Control": "no-store",
            ]
        )!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(asset.data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
