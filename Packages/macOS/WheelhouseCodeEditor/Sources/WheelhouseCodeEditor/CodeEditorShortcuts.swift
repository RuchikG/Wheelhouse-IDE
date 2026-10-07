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

    /// What a folder tab handles besides: find a file (⌘P), search in files (⇧⌘F) and
    /// save all (⌥⌘S).
    static func claimsInProject(characters: String, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        switch (modifierFlags.intersection([.command, .shift, .option, .control]), characters.lowercased()) {
        case ([.command], "p"), ([.command, .shift], "f"), ([.command, .option], "s"): return true
        default: return false
        }
    }

    /// Whether the editor that has keyboard focus, if one has, handles this key itself.
    @MainActor
    public static func focusedEditorClaims(
        characters: String, modifierFlags: NSEvent.ModifierFlags, firstResponder: NSResponder?
    ) -> Bool {
        guard let editor = focusedEditor(firstResponder: firstResponder) else { return false }
        return claims(characters: characters, modifierFlags: modifierFlags)
            || (editor.showsProject && claimsInProject(characters: characters, modifierFlags: modifierFlags))
    }

    @MainActor
    public static func isEditorFocused(firstResponder: NSResponder?) -> Bool {
        focusedEditor(firstResponder: firstResponder) != nil
    }

    @MainActor
    private static func focusedEditor(firstResponder: NSResponder?) -> CodeEditorWebView? {
        var view = firstResponder as? NSView
        while let current = view {
            if let editor = current as? CodeEditorWebView { return editor }
            view = current.superview
        }
        return nil
    }
}
