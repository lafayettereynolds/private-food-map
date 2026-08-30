import Foundation
import Testing
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
        #expect(RestaurantBrowseSegment.allCases.map(\.title) == ["去过", "想吃", "适合你"])
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
