import AppKit

/// Container that sizes the editor web view to its bounds.
final class CodeEditorHostView: NSView {
    private(set) weak var hostedWebView: CodeEditorWebView?

    func attach(_ webView: CodeEditorWebView) {
        guard webView.superview !== self else { return }
        webView.removeFromSuperview()
        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)
        hostedWebView = webView
    }

    override func layout() {
        super.layout()
        if let hostedWebView, hostedWebView.superview === self, hostedWebView.frame != bounds {
            hostedWebView.frame = bounds
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
