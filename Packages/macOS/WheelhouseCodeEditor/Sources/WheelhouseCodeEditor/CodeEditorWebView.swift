import AppKit
import WebKit

final class CodeEditorWebView: WKWebView {
    var onPointerDown: (() -> Void)?
    var onBecomeFirstResponder: (() -> Void)?
    /// A folder with its tree is open in the page, which then has shortcuts of its own.
    var showsProject = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onPointerDown?()
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome {
            onBecomeFirstResponder?()
        }
        return didBecome
    }
}
