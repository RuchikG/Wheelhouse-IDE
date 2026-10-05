import AppKit
import WebKit

final class CodeEditorWebView: WKWebView {
    var onPointerDown: (() -> Void)?
    var onBecomeFirstResponder: (() -> Void)?

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
