import Foundation
import Testing
@testable import TasteMap

@Suite("Canonical product design rules")
struct ProductDesignRulesTests {
    @Test("Core UI token scales are centralized and accessibility safe")
    func coreDesignTokensAreCoherent() {
        let spacing = [
            TasteMapDesignTokens.Spacing.hairline,
            TasteMapDesignTokens.Spacing.xxxSmall,
            TasteMapDesignTokens.Spacing.xxSmall,
            TasteMapDesignTokens.Spacing.xSmall,
            TasteMapDesignTokens.Spacing.compact,
            TasteMapDesignTokens.Spacing.small,
            TasteMapDesignTokens.Spacing.medium,
            TasteMapDesignTokens.Spacing.regular,
            TasteMapDesignTokens.Spacing.stateContent,
            TasteMapDesignTokens.Spacing.content,
            TasteMapDesignTokens.Spacing.section,
            TasteMapDesignTokens.Spacing.large,
            TasteMapDesignTokens.Spacing.xLarge,
            TasteMapDesignTokens.Spacing.xxLarge,
            TasteMapDesignTokens.Spacing.hero,
        ]
        let radii = [
            TasteMapDesignTokens.Radius.small,
            TasteMapDesignTokens.Radius.compact,
            TasteMapDesignTokens.Radius.control,
            TasteMapDesignTokens.Radius.medium,
            TasteMapDesignTokens.Radius.emptyArtwork,
            TasteMapDesignTokens.Radius.card,
            TasteMapDesignTokens.Radius.activityCard,
        ]

        #expect(zip(spacing, spacing.dropFirst()).allSatisfy { $0.0 < $0.1 })
        #expect(zip(radii, radii.dropFirst()).allSatisfy { $0.0 < $0.1 })
        #expect(TasteMapDesignTokens.Control.minimumHitTarget >= 44)
        #expect(TasteMapDesignTokens.Control.primaryTabMinimumHeight >= 44)
        #expect(
            TasteMapDesignTokens.Control.chipVisibleHeight
                < TasteMapDesignTokens.Control.minimumHitTarget
        )
        #expect(TasteMapDesignTokens.Border.standard == 1)
        #expect(TasteMapDesignTokens.ImageRatio.restaurantLandscape > 1)
        #expect(TasteMapDesignTokens.ImageRatio.socialPoster < 1)
    }

    @Test("Legacy theme aliases resolve to the formal token layer")
    func legacyThemeAliasesUseFormalTokens() {
        #expect(TasteMapCoreTheme.cardRadius == TasteMapDesignTokens.Radius.card)
        #expect(TasteMapCoreTheme.compactRadius == TasteMapDesignTokens.Radius.compact)
        #expect(TasteMapCoreTheme.pageInset == TasteMapDesignTokens.Layout.pageInset)
        #expect(
            TasteMapCoreTheme.sectionSpacing
                == TasteMapDesignTokens.Layout.standardSectionSpacing
        )
    }

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
