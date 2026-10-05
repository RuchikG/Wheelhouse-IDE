public import AppKit

/// Command-key shortcuts the web editor handles itself while it has keyboard
/// focus, so the host must not act on them first.
public enum CodeEditorShortcuts {
    /// Find in file, add next occurrence to the selection, toggle line comment.
    static let claimedCommandKeys: Set<String> = ["f", "d", "/"]

    /// - Parameter characters: the key's characters without modifiers,
    ///   normalized to the Latin layout by the host.
    public static func claims(characters: String, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        modifierFlags.intersection([.command, .shift, .option, .control]) == .command
            && claimedCommandKeys.contains(characters.lowercased())
    }

    @MainActor
    public static func isEditorFocused(firstResponder: NSResponder?) -> Bool {
        var view = firstResponder as? NSView
        while let current = view {
            if current is CodeEditorWebView { return true }
            view = current.superview
        }
        return false
    }
}
