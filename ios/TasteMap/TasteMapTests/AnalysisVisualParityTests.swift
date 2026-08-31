import Testing
import UIKit
@testable import TasteMap

@Suite("Analysis visual parity")
@MainActor
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

    @Test("Provider image references have stable non-colliding render keys")
    func providerImageKeys() {
        let first = AnalysisImageReference.provider(URL(string: "https://images.example.com/a.jpg")!)
        let equivalent = AnalysisImageReference.provider(URL(string: "https://images.example.com/a.jpg")!)
        let second = AnalysisImageReference.provider(URL(string: "https://images.example.com/b.jpg")!)
        #expect(first.resolutionKey != nil)
        #expect(first.resolutionKey == equivalent.resolutionKey)
        #expect(first.resolutionKey != second.resolutionKey)
    }

    @Test("Official poster QR configuration fails closed for unsafe or missing destinations")
    func posterQRConfiguration() {
        #expect(SharePosterBrandConfiguration.resolve(environment: .production, rawValue: nil).qrDestinationURL == nil)
        #expect(SharePosterBrandConfiguration.resolve(environment: .production, rawValue: "http://tastemap.cn").qrDestinationURL == nil)
        #expect(SharePosterBrandConfiguration.resolve(environment: .production, rawValue: "https://localhost/share").qrDestinationURL == nil)
        #expect(SharePosterBrandConfiguration.resolve(environment: .production, rawValue: "https://taste-map.workers.dev/share").qrDestinationURL == nil)
        #expect(SharePosterBrandConfiguration.resolve(environment: .production, rawValue: "https://api-dev.tastemap.cn/share").qrDestinationURL == nil)
        #expect(SharePosterBrandConfiguration.resolve(environment: .production, rawValue: "https://testflight.apple.com/join/example").qrDestinationURL == nil)
        #expect(SharePosterBrandConfiguration.resolve(environment: .production, rawValue: "https://tastemap.example/share").qrDestinationURL?.absoluteString == "https://tastemap.example/share")
    }

    @Test("Configured poster destination renders a real QR image")
    func posterQRCodeRendering() {
        let image = SharePosterQRCodeRenderer.image(for: URL(string: "https://tastemap.example/share")!)
        #expect(image != nil)
        #expect((image?.cgImage?.width ?? 0) > 100)
        #expect((image?.cgImage?.height ?? 0) > 100)
    }
}
