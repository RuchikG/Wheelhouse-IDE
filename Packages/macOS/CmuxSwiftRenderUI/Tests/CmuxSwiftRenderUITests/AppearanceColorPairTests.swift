import AppKit
@testable import CmuxSwiftRenderUI
import SwiftUI
import Testing

@MainActor
@Suite struct AppearanceColorPairTests {
    private func components(_ color: Color, in appearanceName: NSAppearance.Name) throws -> [Int] {
        let appearance = try #require(NSAppearance(named: appearanceName))
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.sRGB)
        }
        let srgb = try #require(resolved)
        return [srgb.redComponent, srgb.greenComponent, srgb.blueComponent].map { Int(($0 * 255).rounded()) }
    }

    @Test func aPairFollowsTheAppearance() throws {
        let color = try #require(dslColor("#102030|#A0B0C0"))
        #expect(try components(color, in: .aqua) == [0x10, 0x20, 0x30])
        #expect(try components(color, in: .darkAqua) == [0xA0, 0xB0, 0xC0])
    }

    @Test func aPairWithAnUnknownSideIsNoColor() {
        #expect(dslColor("#102030|nonsense") == nil)
        #expect(dslColor("|#102030") == nil)
    }

    @Test func aSingleTokenIsUnchanged() throws {
        let color = try #require(dslColor("#102030"))
        #expect(try components(color, in: .darkAqua) == [0x10, 0x20, 0x30])
    }
}
