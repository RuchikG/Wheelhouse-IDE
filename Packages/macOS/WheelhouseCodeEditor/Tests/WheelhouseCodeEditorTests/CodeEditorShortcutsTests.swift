import AppKit
import Testing
@testable import WheelhouseCodeEditor

@Suite struct CodeEditorShortcutsTests {
    @Test func claimsFindNextOccurrenceAndToggleComment() {
        for key in ["f", "d", "/", "F"] {
            #expect(CodeEditorShortcuts.claims(characters: key, modifierFlags: .command))
        }
    }

    @Test func ignoresLockAndKeypadFlags() {
        #expect(CodeEditorShortcuts.claims(characters: "f", modifierFlags: [.command, .capsLock, .numericPad]))
    }

    @Test func leavesOtherKeysAndModifierCombinationsToTheHost() {
        #expect(!CodeEditorShortcuts.claims(characters: "t", modifierFlags: .command))
        #expect(!CodeEditorShortcuts.claims(characters: "f", modifierFlags: []))
        #expect(!CodeEditorShortcuts.claims(characters: "f", modifierFlags: [.command, .shift]))
        #expect(!CodeEditorShortcuts.claims(characters: "d", modifierFlags: [.command, .option]))
        #expect(!CodeEditorShortcuts.claims(characters: "d", modifierFlags: .control))
    }

    @MainActor
    @Test func recognizesFocusInsideTheEditorWebViewOnly() {
        let webView = CodeEditorWebView()
        let inner = NSView()
        webView.addSubview(inner)
        #expect(CodeEditorShortcuts.isEditorFocused(firstResponder: webView))
        #expect(CodeEditorShortcuts.isEditorFocused(firstResponder: inner))
        #expect(!CodeEditorShortcuts.isEditorFocused(firstResponder: NSTextView()))
        #expect(!CodeEditorShortcuts.isEditorFocused(firstResponder: nil))
    }
}
