import Foundation
import Testing
@testable import TasteMap

struct TasteMapCoreThemeTests {
    @Test("Core palette remains aligned with the approved Web visual source")
    func webPaletteContract() {
        #expect(TasteMapCorePaletteContract.webBrand.hex == "#506C8C")
        #expect(TasteMapCorePaletteContract.webBrandDeep.hex == "#344F69")
        #expect(TasteMapCorePaletteContract.webBackground.hex == "#F7F7F5")
        #expect(TasteMapCorePaletteContract.webSurface.hex == "#FFFFFF")
        #expect(TasteMapCorePaletteContract.webTextPrimary.hex == "#172A3A")
        #expect(TasteMapCorePaletteContract.webDivider.hex == "#E3E6E8")
    }

    @Test("Approved primary text and brand button pairs retain readable contrast")
    func coreContrast() {
        #expect(contrast(
            TasteMapCorePaletteContract.webTextPrimary,
            TasteMapCorePaletteContract.webSurface
        ) >= 4.5)
        #expect(contrast(
            TasteMapCorePaletteContract.webSurface,
            TasteMapCorePaletteContract.webBrand
        ) >= 4.5)
        #expect(contrast(
            TasteMapCoreDarkPaletteContract.textPrimary,
            TasteMapCoreDarkPaletteContract.surface
        ) >= 4.5)
        #expect(contrast(
            TasteMapCoreDarkPaletteContract.textPrimary,
            TasteMapCoreDarkPaletteContract.background
        ) >= 4.5)
    }

    private func contrast(_ foreground: CoreRGB, _ background: CoreRGB) -> Double {
        let light = relativeLuminance(foreground)
        let dark = relativeLuminance(background)
        return (max(light, dark) + 0.05) / (min(light, dark) + 0.05)
    }

    private func relativeLuminance(_ color: CoreRGB) -> Double {
        func linear(_ channel: Int) -> Double {
            let value = Double(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red)
            + 0.7152 * linear(color.green)
            + 0.0722 * linear(color.blue)
    }
}
