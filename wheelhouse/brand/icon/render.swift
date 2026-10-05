// Renders wheelhouse-ide.svg to a PNG of the given pixel size.
//   swiftc -parse-as-library render.swift -o render && ./render <svg> <size> <out.png>
import AppKit

@main
enum RenderIcon {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 4, let size = Int(arguments[2]), size > 0,
              let image = NSImage(contentsOfFile: arguments[1]) else {
            FileHandle.standardError.write(Data("usage: render <svg> <size> <out.png>\n".utf8))
            exit(2)
        }
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { exit(1) }
        bitmap.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        try png.write(to: URL(fileURLWithPath: arguments[3]))
    }
}
