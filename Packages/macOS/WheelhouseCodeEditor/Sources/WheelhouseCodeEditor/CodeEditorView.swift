public import AppKit
public import Foundation
public import SwiftUI

/// A Monaco-based code editor for one file, hosted in a web view.
///
/// The owner holds the document: it passes the current content down and
/// receives edits and save requests through the callbacks.
public struct CodeEditorView: NSViewRepresentable {
    private let assetDirectory: URL
    private let document: CodeEditorDocument
    private let options: CodeEditorOptions
    private let theme: CodeEditorTheme
    private let isVisible: Bool
    private let onContentChange: @MainActor (String) -> Void
    private let onSave: @MainActor (String) -> Void
    private let onPointerDown: @MainActor () -> Void
    private let onOpenFile: @MainActor (String) -> Void
    private let onAttach: @MainActor (_ root: NSView, _ responder: NSView) -> Void

    /// - Parameters:
    ///   - assetDirectory: Directory holding `code-editor.html` and its bundle.
    ///   - onContentChange: The edited content, shortly after typing pauses.
    ///   - onSave: The current content when the user asks to save.
    ///   - onOpenFile: Another file the editor wants shown, for example the
    ///     target of go to definition. Its position is revealed by the editor
    ///     that ends up showing the file.
    ///   - onAttach: The container and the view that takes keyboard focus,
    ///     reported whenever the editor is (re)attached.
    public init(
        assetDirectory: URL,
        document: CodeEditorDocument,
        options: CodeEditorOptions,
        theme: CodeEditorTheme,
        isVisible: Bool = true,
        onContentChange: @escaping @MainActor (String) -> Void,
        onSave: @escaping @MainActor (String) -> Void,
        onPointerDown: @escaping @MainActor () -> Void = {},
        onOpenFile: @escaping @MainActor (String) -> Void = { _ in },
        onAttach: @escaping @MainActor (_ root: NSView, _ responder: NSView) -> Void = { _, _ in }
    ) {
        self.assetDirectory = assetDirectory
        self.document = document
        self.options = options
        self.theme = theme
        self.isVisible = isVisible
        self.onContentChange = onContentChange
        self.onSave = onSave
        self.onPointerDown = onPointerDown
        self.onOpenFile = onOpenFile
        self.onAttach = onAttach
    }

    public func makeCoordinator() -> CodeEditorCoordinator {
        CodeEditorCoordinator()
    }

    public func makeNSView(context: Context) -> NSView {
        let host = CodeEditorHostView()
        apply(to: host, coordinator: context.coordinator)
        return host
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let host = nsView as? CodeEditorHostView else { return }
        apply(to: host, coordinator: context.coordinator)
    }

    public static func dismantleNSView(_ nsView: NSView, coordinator: CodeEditorCoordinator) {
        coordinator.close()
    }

    private func apply(to host: CodeEditorHostView, coordinator: CodeEditorCoordinator) {
        coordinator.onContentChange = onContentChange
        coordinator.onSave = onSave
        coordinator.onPointerDown = onPointerDown
        coordinator.onOpenFile = onOpenFile
        let webView = coordinator.ensureWebView(assetDirectory: assetDirectory)
        host.attach(webView)
        host.isHidden = !isVisible
        coordinator.update(document: document, options: options, theme: theme)
        onAttach(host, webView)
    }
}
