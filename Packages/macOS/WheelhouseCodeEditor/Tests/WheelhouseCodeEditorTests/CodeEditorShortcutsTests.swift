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

    @Test func aFolderTabAlsoClaimsFindFileSearchAndSaveAll() {
        #expect(CodeEditorShortcuts.claimsInProject(characters: "p", modifierFlags: .command))
        #expect(CodeEditorShortcuts.claimsInProject(characters: "F", modifierFlags: [.command, .shift]))
        #expect(CodeEditorShortcuts.claimsInProject(characters: "s", modifierFlags: [.command, .option, .capsLock]))
        #expect(!CodeEditorShortcuts.claimsInProject(characters: "p", modifierFlags: [.command, .shift]))
        #expect(!CodeEditorShortcuts.claimsInProject(characters: "s", modifierFlags: .command))
    }

    @MainActor
    @Test func onlyAFocusedFolderTabClaimsTheFolderShortcuts() {
        let single = CodeEditorWebView()
        let folder = CodeEditorWebView()
        folder.showsProject = true
        let claims = { (key: String, flags: NSEvent.ModifierFlags, responder: NSResponder?) in
            CodeEditorShortcuts.focusedEditorClaims(characters: key, modifierFlags: flags, firstResponder: responder)
        }
        #expect(claims("p", .command, folder))
        #expect(claims("f", .command, folder))
        #expect(!claims("p", .command, single))
        #expect(claims("f", .command, single))
        #expect(!claims("p", .command, NSTextView()))
        #expect(!claims("f", .command, nil))
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
