import AppKit
import CmuxCore
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

/// Folders on remote hosts, shown as folder tabs.
///
/// A file tab is a path on this Mac, so a remote folder is stood in for by an
/// empty folder whose own path spells the host and the remote path:
/// `<directory>/<host>/<remote path>`. Opening that folder opens the remote
/// one, which also brings the tab back with the session after a restart.
enum FilePreviewRemoteFolders {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "wheelhouse", isDirectory: true)
            .appendingPathComponent("Remote", isDirectory: true)
    }

    /// Creates the stand-in for `remotePath` (absolute) on `host` and returns its path.
    static func standIn(host: String, remotePath: String) -> String? {
        guard remotePath.hasPrefix("/"), !host.isEmpty, !host.contains("/"), host != ".", host != ".." else { return nil }
        let folder = directory.appendingPathComponent(host, isDirectory: true).path + remotePath
        do {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return (folder as NSString).standardizingPath
    }

    /// The host and remote path a stand-in folder stands for; `nil` for any other path.
    static func remoteFolder(forStandIn path: String) -> (host: String, path: String)? {
        let prefix = (directory.path as NSString).standardizingPath + "/"
        let standardized = (path as NSString).standardizingPath
        guard standardized.hasPrefix(prefix) else { return nil }
        let rest = standardized.dropFirst(prefix.count)
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        return (String(rest[..<slash]), String(rest[slash...]))
    }

    /// How to reach `host`: the way the tab's workspace reaches it when that
    /// workspace is connected to the same host, otherwise as `ssh <host>` would.
    @MainActor
    static func connection(to host: String, from workspace: Workspace?) -> CodeEditorRemoteHost {
        guard let configuration = workspace?.remoteConfiguration,
              configuration.transport == .ssh, configuration.destination == host else {
            return .host(destination: host)
        }
        let arguments = configuration.batchSSHCommandArguments(
            command: "", effectiveSSHOptions: configuration.sshOptions
        )
        return CodeEditorRemoteHost(
            name: host,
            sshArguments: Array(arguments.dropLast()),
            environment: configuration.sshProcessEnvironment
        )
    }
}

extension FilePreviewPanel {
    /// What the tab's header shows as its path: `host:path` for a remote folder.
    var headerPath: String {
        FilePreviewRemoteFolders.remoteFolder(forStandIn: filePath).map { "\($0.host):\($0.path)" } ?? filePath
    }

    /// The folder this tab shows as a project, on this Mac or on a remote host.
    @MainActor
    var editorProject: CodeEditorProject {
        guard let remote = FilePreviewRemoteFolders.remoteFolder(forStandIn: filePath) else {
            return CodeEditorProject(rootPath: filePath)
        }
        return CodeEditorProject(
            rootPath: remote.path,
            remote: FilePreviewRemoteFolders.connection(to: remote.host, from: tabMetadataHost as? Workspace)
        )
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
                project: panel.editorProject,
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
