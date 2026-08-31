import Foundation
import SwiftUI
import Testing
import UIKit
@testable import TasteMap

@Suite("Map Discovery Profile product layout contracts")
@MainActor
struct CoreProductLayoutParityTests {
    @Test("Discovery primary navigation preserves the Web product order")
    func discoveryPrimaryOrder() {
        #expect(DiscoverHubSection.allCases.map(\.title) == [
            "关注", "为你推荐", "同味之选", "最新", "趋势",
        ])
        #expect(DiscoverHubSection.following.communityScope == .following)
        #expect(DiscoverHubSection.latest.communityScope == .latest)
        #expect(DiscoverHubSection.forYou.discoveryMode == .forYou)
        #expect(DiscoverHubSection.similarTaste.discoveryMode == .similarTaste)
        #expect(DiscoverHubSection.trending.discoveryMode == .trending)
    }

    @Test("Map collection navigation remains compact and product ordered")
    func mapCollectionOrder() {
        #expect(RestaurantBrowseSegment.allCases.map(\.title) == ["去过", "想吃", "推荐"])
    }

    @Test("My Map control layers follow the confirmed independent hierarchy")
    func mapControlHierarchy() {
        #expect(MapHomeControlLayer.allCases == [
            .title, .restaurantScope, .filters,
        ])
    }

    @Test("My Map and My List title switch has locked title icon and accessibility semantics")
    func mapTitleSwitchContract() {
        #expect(MapBrowseMode.map.pageTitle == "我的地图")
        #expect(MapBrowseMode.map.systemImage == "map")
        #expect(MapBrowseMode.map.switchAccessibilityLabel == "切换到我的列表")
        #expect(MapBrowseMode.list.pageTitle == "我的列表")
        #expect(MapBrowseMode.list.systemImage == "list.bullet")
        #expect(MapBrowseMode.list.switchAccessibilityLabel == "切换到我的地图")
    }

    @Test("Title and icon remain one compact group at small iPhone width")
    func mapTitleSwitchSmallWidth() {
        let host = UIHostingController(
            rootView: MapBrowseTitleSwitch(browseMode: .constant(.map))
        )
        let size = host.sizeThatFits(in: CGSize(width: 320, height: 64))
        #expect(size.width > 0)
        #expect(size.width <= 320)
        #expect(size.height <= 64)
    }

    @Test("Map filter chips use one semantic icon strategy and city is not GPS")
    func mapFilterIconContract() {
        let semantics: [TasteMapFilterSemantic] = [
            .city, .rating, .price, .visitCount, .companion, .cuisine,
            .recommendationSource, .sort,
        ]
        let symbols = semantics.map(\.systemImage)
        #expect(symbols.count == semantics.count)
        #expect(symbols.allSatisfy { !$0.isEmpty })
        #expect(TasteMapFilterSemantic.city.systemImage == "building.2.fill")
        #expect(!TasteMapFilterSemantic.city.systemImage.localizedCaseInsensitiveContains("location"))
        #expect(!TasteMapFilterSemantic.city.systemImage.localizedCaseInsensitiveContains("mappin"))
    }

    @Test("Core Food and Dining decorative selection is stable and bounded")
    func stableCoreDiningVisuals() {
        let seed = "empty-state|restaurant-a|restaurant-b"
        let first = FoodDiningVisualLibrary.decorativeKind(stableSeed: seed)
        let repeated = FoodDiningVisualLibrary.decorativeKind(stableSeed: seed)
        #expect(first == repeated)
        #expect(FoodDiningVisualLibrary.decorativeCoreKinds.contains(first))
        #expect(!FoodDiningVisualLibrary.decorativeCoreKinds.isEmpty)
    }

    @Test("Profile dashboard statistics keep one shared horizontal data source")
    func profileStatisticsContract() {
        let statistics = ProfileBasicStatistics(
            visitedRestaurantCount: 12,
            wantToGoRestaurantCount: 5,
            visitCount: 20,
            averageRating: 4.25,
            totalSpend: 1_888
        )
        #expect(statistics.visitedRestaurantCount == 12)
        #expect(statistics.wantToGoRestaurantCount == 5)
        #expect(statistics.visitCount == 20)
        #expect(statistics.averageRating == 4.25)
        #expect(statistics.totalSpend == 1_888)
    }
}
