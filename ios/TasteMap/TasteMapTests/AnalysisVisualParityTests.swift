import Testing
import UIKit
@testable import TasteMap

@Suite("Analysis visual parity")
struct AnalysisVisualParityTests {
    @Test("Analysis retains its approved warm-white editorial palette")
    func approvedAnalysisPalette() {
        #expect(TasteMapAnalysisPaletteContract.brand.hex == "#506C8C")
        #expect(TasteMapAnalysisPaletteContract.brandDeep.hex == "#344F69")
        #expect(TasteMapAnalysisPaletteContract.canvas.hex == "#FBFAF7")
        #expect(TasteMapAnalysisPaletteContract.card.hex == "#FFFFFF")
        #expect(TasteMapAnalysisPaletteContract.ink.hex == "#24313C")
        #expect(TasteMapAnalysisPaletteContract.secondaryInk.hex == "#667179")
        #expect(TasteMapAnalysisPaletteContract.hairline.hex == "#E2E5E2")
        #expect(TasteMapAnalysisPaletteContract.canvas != TasteMapCorePaletteContract.webBackground)
    }

    @Test("Food and Dining semantics replace legacy emoji deterministically")
    func semanticVisualMapping() {
        #expect(FoodDiningVisualLibrary.kind(semanticID: "spend", legacySymbol: "🍽️") == .receipt)
        #expect(FoodDiningVisualLibrary.kind(semanticID: "rating", legacySymbol: "🥢") == .rating)
        #expect(FoodDiningVisualLibrary.kind(semanticID: "annual-companion", legacySymbol: "🧾") == .sharedMeal)
        #expect(FoodDiningVisualLibrary.kind(semanticID: "repeat", legacySymbol: "⭐️") == .repeatVisit)
        #expect(FoodDiningVisualLibrary.kind(semanticID: "visits") == .tableware)
        #expect(FoodDiningVisualLibrary.kind(semanticID: "recent-meal") == .calendar)
        #expect(FoodDiningVisualLibrary.kind(legacySymbol: "📸") == .photo)
        #expect(FoodDiningVisualLibrary.kind(legacySymbol: "🍲") == .food)
        #expect(FoodDiningVisualLibrary.kind() == .genericDining)
    }

    @Test("Approved dynamic Food Hero illustrations remain bundled")
    func foodHeroAssets() {
        for asset in [
            "FoodHeroJapanese", "FoodHeroHotpotGrill", "FoodHeroChinese",
            "FoodHeroWestern", "FoodHeroCafe", "FoodHeroMixed",
        ] {
            #expect(UIImage(named: asset) != nil, "Missing approved Food Hero asset: \(asset)")
        }
    }
}
