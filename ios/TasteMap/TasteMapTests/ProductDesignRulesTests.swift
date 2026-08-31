import Foundation
import Testing
@testable import TasteMap

@Suite("Canonical product design rules")
struct ProductDesignRulesTests {
    @Test("Every filter semantic owns one nonempty icon")
    func filterSemanticsAreComplete() {
        let symbols = TasteMapFilterSemantic.allCases.map(\.systemImage)
        #expect(symbols.count == TasteMapFilterSemantic.allCases.count)
        #expect(symbols.allSatisfy { !$0.isEmpty })
    }

    @Test("Static city never uses GPS semantics")
    func cityUsesBuildingSemantics() {
        let symbol = TasteMapFilterSemantic.city.systemImage
        #expect(symbol == "building.2.fill")
        #expect(!symbol.localizedCaseInsensitiveContains("location"))
        #expect(!symbol.localizedCaseInsensitiveContains("mappin"))
    }

    @Test("Decorative Food Dining selection is stable")
    func decorativeVisualIsStable() {
        let first = FoodDiningVisualLibrary.decorativeKind(stableSeed: "stable-scene")
        let second = FoodDiningVisualLibrary.decorativeKind(stableSeed: "stable-scene")
        #expect(first == second)
        #expect(FoodDiningVisualLibrary.decorativeCoreKinds.contains(first))
    }
}
