public import AppKit

/// Host colors applied on top of the editor's built-in light or dark theme.
public struct CodeEditorTheme: Equatable, Sendable, Encodable {
    public var isDark: Bool
    /// `#RRGGBB` or `#RRGGBBAA`.
    public var background: String
    public var foreground: String

    public init(isDark: Bool, background: String, foreground: String) {
        self.isDark = isDark
        self.background = background
        self.foreground = foreground
    }

    /// Derives the theme from the host panel's colors; dark when the background is.
    public init(background: NSColor, foreground: NSColor) {
        let resolvedBackground = background.usingColorSpace(.sRGB) ?? .black
        let luminance = 0.2126 * resolvedBackground.redComponent
            + 0.7152 * resolvedBackground.greenComponent
            + 0.0722 * resolvedBackground.blueComponent
        self.init(
            isDark: luminance < 0.5,
            background: Self.hexString(background),
            foreground: Self.hexString(foreground)
        )
    }

    static func hexString(_ color: NSColor) -> String {
        guard let color = color.usingColorSpace(.sRGB) else { return "#000000" }
        func byte(_ component: CGFloat) -> Int {
            Int((min(max(component, 0), 1) * 255).rounded())
        }
        let rgb = String(
            format: "#%02X%02X%02X",
            byte(color.redComponent), byte(color.greenComponent), byte(color.blueComponent)
        )
        let alpha = byte(color.alphaComponent)
        return alpha == 255 ? rgb : rgb + String(format: "%02X", alpha)
    }
}
