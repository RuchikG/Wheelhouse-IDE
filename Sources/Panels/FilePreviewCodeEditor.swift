import AppKit
import CmuxSettings
import CmuxSettingsUI
import SwiftUI
import WheelhouseCodeEditor

/// Text-mode renderer for `FilePreviewPanel` backed by the web code editor.
/// The panel stays the owner of content, dirty state and saving.
struct FilePreviewCodeEditor: View {
    @ObservedObject var panel: FilePreviewPanel
    let isVisibleInUI: Bool
    let themeBackgroundColor: NSColor
    let themeForegroundColor: NSColor
    let wordWrap: Bool
    let onRequestPanelFocus: () -> Void

    @LiveSetting(\.fileEditor.lineNumbers) private var lineNumbers
    @LiveSetting(\.fileEditor.indentGuides) private var indentGuides
    @LiveSetting(\.fileEditor.currentLineHighlight) private var currentLineHighlight
    @LiveSetting(\.fileEditor.tabWidth) private var tabWidth

    private static let assetDirectory = Bundle.main.resourceURL?
        .appendingPathComponent("markdown-viewer", isDirectory: true)
        .appendingPathComponent("webviews-app", isDirectory: true)

    var body: some View {
        if let assetDirectory = Self.assetDirectory {
            CodeEditorView(
                assetDirectory: assetDirectory,
                document: CodeEditorDocument(
                    path: panel.filePath,
                    content: panel.textContent,
                    contentRevision: panel.textContentRevision,
                    isReadOnly: panel.cloudPreviewLease != nil
                ),
                options: CodeEditorOptions(
                    wordWrap: wordWrap,
                    lineNumbers: lineNumbers,
                    indentGuides: indentGuides,
                    currentLineHighlight: currentLineHighlight,
                    tabWidth: tabWidth
                ),
                theme: CodeEditorTheme(background: themeBackgroundColor, foreground: themeForegroundColor),
                isVisible: isVisibleInUI,
                onContentChange: { [weak panel] content in
                    panel?.updateTextContent(content)
                },
                onSave: { [weak panel] content in
                    panel?.updateTextContent(content)
                    panel?.saveTextContent()
                },
                onPointerDown: onRequestPanelFocus,
                onOpenFile: { [weak panel] path in
                    panel?.openFileInSamePane(path)
                },
                onAttach: { [weak panel] root, responder in
                    panel?.attachPreviewFocus(root: root, primaryResponder: responder, intent: .textEditor)
                }
            )
        }
    }
}

/// The editors of open folder tabs. A folder tab's open files and unsaved
/// edits live in its editor, so the editor is kept for as long as the tab
/// exists, also while the tab is off screen in another workspace.
@MainActor
enum FilePreviewProjectEditors {
    private static var coordinators: [UUID: CodeEditorCoordinator] = [:]

    static func coordinator(for panel: FilePreviewPanel) -> CodeEditorCoordinator {
        if let coordinator = coordinators[panel.id] { return coordinator }
        let coordinator = CodeEditorCoordinator()
        coordinators[panel.id] = coordinator
        return coordinator
    }

    static func close(_ panel: FilePreviewPanel) {
        coordinators.removeValue(forKey: panel.id)?.close()
    }
}

/// Renderer for a `FilePreviewPanel` whose path is a folder: the project
/// editor, which lists, opens and saves the folder's files itself.
struct FilePreviewProjectEditor: View {
    @ObservedObject var panel: FilePreviewPanel
    let isVisibleInUI: Bool
    let themeBackgroundColor: NSColor
    let themeForegroundColor: NSColor
    let wordWrap: Bool
    let onRequestPanelFocus: () -> Void

    @LiveSetting(\.fileEditor.lineNumbers) private var lineNumbers
    @LiveSetting(\.fileEditor.indentGuides) private var indentGuides
    @LiveSetting(\.fileEditor.currentLineHighlight) private var currentLineHighlight
    @LiveSetting(\.fileEditor.tabWidth) private var tabWidth

    private static let assetDirectory = Bundle.main.resourceURL?
        .appendingPathComponent("markdown-viewer", isDirectory: true)
        .appendingPathComponent("webviews-app", isDirectory: true)

    var body: some View {
        // A closed tab has given up its editor; drawing it again would start a new one.
        if let assetDirectory = Self.assetDirectory, !panel.isClosed {
            ProjectEditorView(
                coordinator: FilePreviewProjectEditors.coordinator(for: panel),
                assetDirectory: assetDirectory,
                project: CodeEditorProject(rootPath: panel.filePath),
                options: CodeEditorOptions(
                    wordWrap: wordWrap,
                    lineNumbers: lineNumbers,
                    indentGuides: indentGuides,
                    currentLineHighlight: currentLineHighlight,
                    tabWidth: tabWidth
                ),
                theme: CodeEditorTheme(background: themeBackgroundColor, foreground: themeForegroundColor),
                isVisible: isVisibleInUI,
                onDirtyChange: { [weak panel] isDirty in
                    panel?.setProjectHasUnsavedFiles(isDirty)
                },
                onPointerDown: onRequestPanelFocus,
                onAttach: { [weak panel] root, responder in
                    panel?.attachPreviewFocus(root: root, primaryResponder: responder, intent: .textEditor)
                }
            )
        }
    }
}
