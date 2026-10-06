import AppKit
import CmuxCore
import Bonsplit
import WheelhouseCodeEditor

/// What a new editor tab starts with.
enum NewEditorTabKind {
    /// An empty file that asks where to live the first time it is saved.
    case untitled
    /// Files picked in an open panel.
    case chosenFiles
    /// A folder picked in an open panel, shown as a project: file tree and editor in one tab.
    case chosenFolder
}

@MainActor
enum NewEditorTabPanel {
    nonisolated static var title: String {
        String(localized: "wheelhouse.newEditorTab.title", defaultValue: "New Editor Tab")
    }

    nonisolated static var untitledTitle: String {
        String(localized: "wheelhouse.newEditorTab.untitled", defaultValue: "New Untitled File")
    }

    nonisolated static var openFileTitle: String {
        String(localized: "wheelhouse.newEditorTab.openFile", defaultValue: "Open File…")
    }

    nonisolated static var openFolderTitle: String {
        String(localized: "wheelhouse.newEditorTab.openFolder", defaultValue: "Open Folder…")
    }

    /// The chosen file paths, or the chosen folder; empty when the panel was cancelled.
    static func choose(folder: Bool, startDirectory: String?) -> [String] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !folder
        panel.canChooseDirectories = folder
        panel.allowsMultipleSelection = !folder
        panel.title = title
        panel.prompt = String(localized: "wheelhouse.newEditorTab.panelPrompt", defaultValue: "Open")
        if let directoryURL = directoryURL(startDirectory) {
            panel.directoryURL = directoryURL
        }
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.map(\.path)
    }

    /// The file paths for `kind`; empty when there is nothing to open.
    static func filePaths(for kind: NewEditorTabKind, startDirectory: String?) -> [String] {
        switch kind {
        case .untitled:
            return UntitledEditorFiles.create().map { [$0] } ?? []
        case .chosenFiles:
            return choose(folder: false, startDirectory: startDirectory)
        case .chosenFolder:
            return choose(folder: true, startDirectory: startDirectory)
        }
    }

    /// Asks which kind of editor tab to open, at the pointer.
    static func chooseKind() -> NewEditorTabKind? {
        var chosen: NewEditorTabKind?
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(title: untitledTitle) { chosen = .untitled })
        menu.addItem(ClosureMenuItem(title: openFileTitle) { chosen = .chosenFiles })
        menu.addItem(ClosureMenuItem(title: openFolderTitle) { chosen = .chosenFolder })
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        return chosen
    }

    /// Asks for a folder on `host`, starting from `suggestion`. `nil` when cancelled.
    static func askRemoteFolder(on host: String, suggestion: String?) -> String? {
        let alert = NSAlert()
        alert.messageText = String(
            localized: "wheelhouse.remoteFolder.title", defaultValue: "Open a folder on \(host)"
        )
        alert.informativeText = String(
            localized: "wheelhouse.remoteFolder.message",
            defaultValue: "Its files are edited and saved on that host, and language features run there."
        )
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.stringValue = suggestion ?? "~"
        field.placeholderString = "~/project"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: String(localized: "wheelhouse.newEditorTab.panelPrompt", defaultValue: "Open"))
        alert.addButton(withTitle: String(localized: "wheelhouse.remoteFolder.cancel", defaultValue: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let folder = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return folder.isEmpty ? nil : folder
    }

    static func reportRemoteFolderFailure(_ folder: String, on host: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(
            localized: "wheelhouse.remoteFolder.failed", defaultValue: "“\(folder)” could not be opened on \(host)"
        )
        alert.informativeText = message
        alert.runModal()
    }

    static func directoryURL(_ path: String?) -> URL? {
        let directory = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !directory.isEmpty else { return nil }
        return URL(fileURLWithPath: (directory as NSString).expandingTildeInPath, isDirectory: true)
    }
}

/// Menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        handler()
    }
}

/// Empty files that back untitled editor tabs until they are saved somewhere.
enum UntitledEditorFiles {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "wheelhouse", isDirectory: true)
            .appendingPathComponent("Untitled", isDirectory: true)
    }

    static func contains(_ filePath: String) -> Bool {
        URL(fileURLWithPath: filePath).deletingLastPathComponent().standardizedFileURL.path
            == directory.standardizedFileURL.path
    }

    /// Creates the next free `Untitled-<n>` file and returns its path.
    static func create() -> String? {
        let fileManager = FileManager.default
        let directory = directory
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        for number in 1...999 {
            let path = directory.appendingPathComponent("Untitled-\(number)").path
            if !fileManager.fileExists(atPath: path) {
                return fileManager.createFile(atPath: path, contents: nil) ? path : nil
            }
        }
        return nil
    }

    static func remove(_ filePath: String) {
        guard contains(filePath) else { return }
        try? FileManager.default.removeItem(atPath: filePath)
    }
}

extension FilePreviewPanel {
    var isUntitled: Bool {
        UntitledEditorFiles.contains(filePath)
    }

    /// Whether a folder opens as a project tab; it needs the web code editor.
    static var showsFoldersAsProjects: Bool {
        UserDefaults.standard.object(forKey: CodeEditorPreference.enabledKey) as? Bool
            ?? CodeEditorPreference.enabledByDefault
    }

    /// A folder is shown as a project instead of as one file.
    var isFolder: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Saving an untitled file: asks where, writes `content` there, and puts a
    /// tab for the new file in this tab's place.
    func saveUntitledContent(_ content: String) {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = String(
            localized: "wheelhouse.untitled.defaultFileName", defaultValue: "untitled.txt"
        )
        let workspace = tabMetadataHost as? Workspace
        if let directoryURL = NewEditorTabPanel.directoryURL(workspace?.resolvedWorkingDirectory()) {
            savePanel.directoryURL = directoryURL
        }
        guard savePanel.runModal() == .OK, let destination = savePanel.url else { return }
        do {
            try Data(content.utf8).write(to: destination, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        guard let location = tabLocation else { return }
        if let workspace {
            _ = workspace.openFileSurfaces(
                inPane: location.paneId, filePaths: [destination.path], focus: true, targetIndex: location.index + 1
            )
            _ = workspace.closePanel(id, force: true)
        } else if let dock = location.host as? DockSplitStore {
            _ = dock.openFilePreviewSurfaces(
                inPane: location.paneId, filePaths: [destination.path], focus: true, targetIndex: location.index + 1
            )
            _ = dock.closePanel(id, force: true)
        }
    }

    /// Shows another file in this tab's pane, focusing its tab when it is
    /// already open. Used for jumps out of the editor such as go to definition.
    func openFileInSamePane(_ path: String) {
        guard let location = tabLocation else { return }
        if let workspace = location.host as? Workspace {
            _ = workspace.openFileSurfaces(inPane: location.paneId, filePaths: [path], focus: true, reuseExisting: true)
        } else if let dock = location.host as? DockSplitStore {
            _ = dock.openFilePreviewSurfaces(inPane: location.paneId, filePaths: [path], focus: true)
        }
    }

    /// The container, pane and position of this panel's tab.
    private var tabLocation: (host: any FilePreviewTabMetadataHost, paneId: PaneID, index: Int)? {
        guard let host = tabMetadataHost, let tabId = host.filePreviewTabId(forPanelId: id) else { return nil }
        for paneId in host.bonsplitController.allPaneIds {
            if let index = host.bonsplitController.tabs(inPane: paneId).firstIndex(where: { $0.id == tabId }) {
                return (host, paneId, index)
            }
        }
        return nil
    }

    /// Removes the backing file of an untitled tab the user closed. Tabs still
    /// open at quit keep theirs, so they come back with the session.
    func discardUntitledFileIfClosedByUser() {
        guard isUntitled, AppDelegate.shared?.isTerminatingApp != true else { return }
        UntitledEditorFiles.remove(filePath)
    }
}

extension Workspace {
    /// Opens new editor tabs in `paneId`, after `anchorTabId` when given. A
    /// chosen file that is already open is focused instead of opened twice.
    @discardableResult
    func openNewEditorTabs(
        _ kind: NewEditorTabKind,
        inPane paneId: PaneID,
        toRightOf anchorTabId: TabID? = nil
    ) -> Bool {
        if kind == .chosenFolder, let remote = remoteConfiguration, remote.transport == .ssh {
            return openRemoteFolderTab(on: remote.destination, inPane: paneId, toRightOf: anchorTabId)
        }
        let filePaths = NewEditorTabPanel.filePaths(for: kind, startDirectory: resolvedWorkingDirectory())
        return openEditorTabs(filePaths, inPane: paneId, toRightOf: anchorTabId)
    }

    /// In a workspace connected to another machine, "Open Folder…" means a
    /// folder there: asks for its path, checks it on the host and opens it.
    private func openRemoteFolderTab(on host: String, inPane paneId: PaneID, toRightOf anchorTabId: TabID?) -> Bool {
        guard let folder = NewEditorTabPanel.askRemoteFolder(on: host, suggestion: trustedRemoteCurrentDirectory) else {
            return false
        }
        let connection = FilePreviewRemoteFolders.connection(to: host, from: self)
        Task { @MainActor [weak self] in
            switch await connection.resolveFolder(folder) {
            case .success(let remotePath):
                guard let self,
                      let standIn = FilePreviewRemoteFolders.standIn(host: host, remotePath: remotePath) else { return }
                self.openEditorTabs([standIn], inPane: paneId, toRightOf: anchorTabId)
            case .failure(let failure):
                NewEditorTabPanel.reportRemoteFolderFailure(folder, on: host, message: failure.message)
            }
        }
        return true
    }

    @discardableResult
    private func openEditorTabs(_ filePaths: [String], inPane paneId: PaneID, toRightOf anchorTabId: TabID?) -> Bool {
        guard !filePaths.isEmpty else { return false }
        let existingPanelIds = Set(panels.keys)
        let opened = openFileSurfaces(inPane: paneId, filePaths: filePaths, focus: true, reuseExisting: true)
        if let anchorTabId {
            var targetIndex = insertionIndexToRight(of: anchorTabId, inPane: paneId)
            for panel in opened where !existingPanelIds.contains(panel.id) {
                _ = reorderSurface(panelId: panel.id, toIndex: targetIndex, focus: false)
                targetIndex += 1
            }
        }
        return !opened.isEmpty
    }
}

extension DockSplitStore {
    @discardableResult
    func openNewEditorTabs(_ kind: NewEditorTabKind, inPane paneId: PaneID, toRightOf anchorTabId: TabID) -> Bool {
        let filePaths = NewEditorTabPanel.filePaths(for: kind, startDirectory: nil)
        guard !filePaths.isEmpty else { return false }
        let tabs = bonsplitController.tabs(inPane: paneId)
        let targetIndex = tabs.firstIndex(where: { $0.id == anchorTabId }).map { $0 + 1 }
        return !openFilePreviewSurfaces(inPane: paneId, filePaths: filePaths, focus: true, targetIndex: targetIndex).isEmpty
    }
}

/// Adds "New Editor Tab to Right" to the tab context menu.
///
/// Bonsplit builds that menu and has no slot for host items, so the item is
/// inserted when the menu opens. Bonsplit does not expose which tab was
/// clicked either; choosing an entry replays the menu's own "New Terminal Tab
/// to Right" item with a request pending, and the host handling that action
/// opens editor tabs instead of a terminal.
@MainActor
final class NewEditorTabContextMenuItem: NSObject {
    static let shared = NewEditorTabContextMenuItem()

    private static let itemIdentifier = NSUserInterfaceItemIdentifier("wheelhouse.newEditorTabToRight")
    private var pendingRequest: NewEditorTabKind?
    private var observer: (any NSObjectProtocol)?

    func install() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let menu = notification.object as? NSMenu else { return }
            MainActor.assumeIsolated {
                NewEditorTabContextMenuItem.shared.addItem(to: menu)
            }
        }
    }

    /// The kind that was chosen, once; the caller then opens editor tabs.
    func consumeRequest() -> NewEditorTabKind? {
        defer { pendingRequest = nil }
        return pendingRequest
    }

    private func addItem(to menu: NSMenu) {
        guard !menu.items.contains(where: { $0.identifier == Self.itemIdentifier }),
              let terminalItem = Self.item(for: .newTerminalToRight, in: menu),
              let browserItem = Self.item(for: .newBrowserToRight, in: menu) else { return }
        let item = NSMenuItem(
            title: String(localized: "wheelhouse.newEditorTabToRight.title", defaultValue: "New Editor Tab to Right"),
            action: nil,
            keyEquivalent: ""
        )
        item.identifier = Self.itemIdentifier
        let submenu = NSMenu()
        submenu.addItem(ClosureMenuItem(title: NewEditorTabPanel.untitledTitle) { [weak self] in
            self?.replay(terminalItem, as: .untitled)
        })
        submenu.addItem(ClosureMenuItem(title: NewEditorTabPanel.openFileTitle) { [weak self] in
            self?.replay(terminalItem, as: .chosenFiles)
        })
        submenu.addItem(ClosureMenuItem(title: NewEditorTabPanel.openFolderTitle) { [weak self] in
            self?.replay(terminalItem, as: .chosenFolder)
        })
        item.submenu = submenu
        menu.insertItem(item, at: menu.index(of: browserItem) + 1)
    }

    private static func item(for action: TabContextAction, in menu: NSMenu) -> NSMenuItem? {
        menu.items.first { ($0.representedObject as? String) == action.rawValue }
    }

    private func replay(_ terminalItem: NSMenuItem, as kind: NewEditorTabKind) {
        guard let action = terminalItem.action else { return }
        pendingRequest = kind
        defer { pendingRequest = nil }
        NSApp.sendAction(action, to: terminalItem.target, from: terminalItem)
    }
}
