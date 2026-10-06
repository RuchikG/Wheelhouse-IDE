public import AppKit
public import Foundation
public import SwiftUI

/// A folder as an editor: a file tree, the files opened from it and one
/// Monaco editor, hosted in a web view. Files are read and saved by the view.
public struct ProjectEditorView: NSViewRepresentable {
    private let assetDirectory: URL
    private let project: CodeEditorProject
    private let options: CodeEditorOptions
    private let theme: CodeEditorTheme
    private let isVisible: Bool
    private let onDirtyChange: @MainActor (Bool) -> Void
    private let onPointerDown: @MainActor () -> Void
    private let onAttach: @MainActor (_ root: NSView, _ responder: NSView) -> Void

    /// - Parameters:
    ///   - assetDirectory: Directory holding `code-editor.html` and its bundle.
    ///   - onDirtyChange: Whether any open file has unsaved edits, when that changes.
    ///   - onAttach: The container and the view that takes keyboard focus,
    ///     reported whenever the editor is (re)attached.
    public init(
        assetDirectory: URL,
        project: CodeEditorProject,
        options: CodeEditorOptions,
        theme: CodeEditorTheme,
        isVisible: Bool = true,
        onDirtyChange: @escaping @MainActor (Bool) -> Void = { _ in },
        onPointerDown: @escaping @MainActor () -> Void = {},
        onAttach: @escaping @MainActor (_ root: NSView, _ responder: NSView) -> Void = { _, _ in }
    ) {
        self.assetDirectory = assetDirectory
        self.project = project
        self.options = options
        self.theme = theme
        self.isVisible = isVisible
        self.onDirtyChange = onDirtyChange
        self.onPointerDown = onPointerDown
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
        coordinator.onProjectDirtyChange = onDirtyChange
        coordinator.onPointerDown = onPointerDown
        let webView = coordinator.ensureWebView(assetDirectory: assetDirectory)
        host.attach(webView)
        host.isHidden = !isVisible
        coordinator.update(project: project, options: options, theme: theme)
        onAttach(host, webView)
    }
}
