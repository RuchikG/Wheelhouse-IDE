/// Persisted choice between the web code editor and the host's native editor.
public enum CodeEditorPreference {
    /// UserDefaults key; `false` falls back to the native text editor.
    public static let enabledKey = "wheelhouse.codeEditor.enabled"
    public static let enabledByDefault = true
}
