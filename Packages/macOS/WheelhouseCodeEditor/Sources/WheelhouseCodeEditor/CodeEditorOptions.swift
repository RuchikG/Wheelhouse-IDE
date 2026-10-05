/// Editor preferences forwarded to the web editor.
public struct CodeEditorOptions: Equatable, Sendable, Encodable {
    public var wordWrap: Bool
    public var lineNumbers: Bool
    public var indentGuides: Bool
    public var currentLineHighlight: Bool
    public var tabWidth: Int
    public var fontSize: Double

    public init(
        wordWrap: Bool = false,
        lineNumbers: Bool = true,
        indentGuides: Bool = true,
        currentLineHighlight: Bool = true,
        tabWidth: Int = 4,
        fontSize: Double = 13
    ) {
        self.wordWrap = wordWrap
        self.lineNumbers = lineNumbers
        self.indentGuides = indentGuides
        self.currentLineHighlight = currentLineHighlight
        self.tabWidth = tabWidth
        self.fontSize = fontSize
    }
}
