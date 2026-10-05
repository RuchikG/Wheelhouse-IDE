import AppKit
import Bonsplit

/// "New Editor Tab": asks for files and opens each one as a tab.
@MainActor
enum NewEditorTabPanel {
    nonisolated static var title: String {
        String(localized: "wheelhouse.newEditorTab.title", defaultValue: "New Editor Tab")
    }

    /// The chosen file paths; empty when the panel was cancelled.
    static func chooseFiles(startDirectory: String?) -> [String] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.title = title
        panel.prompt = String(localized: "wheelhouse.newEditorTab.panelPrompt", defaultValue: "Open")
        let directory = startDirectory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !directory.isEmpty {
            panel.directoryURL = URL(
                fileURLWithPath: (directory as NSString).expandingTildeInPath,
                isDirectory: true
            )
        }
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.map(\.path)
    }
}

extension Workspace {
    /// Opens the chosen files in `paneId`; new tabs go after `anchorTabId` when given.
    /// A file that is already open is focused instead of opened twice.
    @discardableResult
    func openNewEditorTabs(inPane paneId: PaneID, toRightOf anchorTabId: TabID? = nil) -> Bool {
        let filePaths = NewEditorTabPanel.chooseFiles(startDirectory: resolvedWorkingDirectory())
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
    func openNewEditorTabs(inPane paneId: PaneID, toRightOf anchorTabId: TabID) -> Bool {
        let filePaths = NewEditorTabPanel.chooseFiles(startDirectory: nil)
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
/// clicked either; choosing the item replays the menu's own "New Terminal Tab
/// to Right" item with a request pending, and the host handling that action
/// opens editor tabs instead of a terminal.
@MainActor
final class NewEditorTabContextMenuItem: NSObject {
    static let shared = NewEditorTabContextMenuItem()

    private static let itemIdentifier = NSUserInterfaceItemIdentifier("wheelhouse.newEditorTabToRight")
    private var isRequestPending = false
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

    /// True once after the item was chosen; the caller then opens editor tabs.
    func consumeRequest() -> Bool {
        defer { isRequestPending = false }
        return isRequestPending
    }

    private func addItem(to menu: NSMenu) {
        guard !menu.items.contains(where: { $0.identifier == Self.itemIdentifier }),
              let terminalItem = Self.item(for: .newTerminalToRight, in: menu),
              let browserItem = Self.item(for: .newBrowserToRight, in: menu) else { return }
        let item = NSMenuItem(
            title: String(localized: "wheelhouse.newEditorTabToRight.title", defaultValue: "New Editor Tab to Right"),
            action: #selector(openEditorTabs(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.identifier = Self.itemIdentifier
        item.representedObject = terminalItem
        menu.insertItem(item, at: menu.index(of: browserItem) + 1)
    }

    private static func item(for action: TabContextAction, in menu: NSMenu) -> NSMenuItem? {
        menu.items.first { ($0.representedObject as? String) == action.rawValue }
    }

    @objc private func openEditorTabs(_ sender: NSMenuItem) {
        guard let terminalItem = sender.representedObject as? NSMenuItem,
              let action = terminalItem.action else { return }
        isRequestPending = true
        defer { isRequestPending = false }
        NSApp.sendAction(action, to: terminalItem.target, from: terminalItem)
    }
}
