import SwiftUI

private struct DiscoveryPreviewHost: View {
    @State var mode: DiscoveryModeV1
    @State var window = 7
    @State var filters = DiscoveryBrowseFilters()
    let cards: [DiscoveryCardV1]
    var loading = false
    var message: String?
    var cached = false
    var signedIn = true

    var body: some View {
        NavigationStack {
            DiscoveryContentView(
                mode: $mode, trendWindowDays: $window, cards: cards,
                unfilteredCardCount: cards.count,
                loading: loading, loadingMore: false, message: message,
                cacheDate: cached ? .now.addingTimeInterval(-1800) : nil,
                showingCache: cached, isSignedIn: signedIn,
                city: "杭州", availableCities: ["杭州", "上海"], filters: $filters,
                filterEmptyReason: nil, distanceAnchorDescription: nil, canLoadMore: false,
                onSelectCity: { _ in }, onResetFilters: {},
                onRetry: {}, onOpenRestaurant: { _ in }, onWantToGo: { _ in },
                onRecordVisit: { _ in }, onAddToList: { _ in }, onAddToRoulette: { _ in },
                onOpenUser: { _ in }, onLoadMore: {}, photoAPI: nil
            )
            .navigationTitle("发现")
            .background(TasteMapCoreTheme.page)
        }
    }
}

private enum DiscoveryPreviewFixtures {
    static let user = DiscoveryPublicUserProjectionV1(
        userId: "tm_preview_friend", displayName: "爱吃寿司的小林", bio: "周末探店",
        city: "杭州", avatarPhotoId: nil, avatarPresetId: .penguin,
        friendshipId: "friend-preview", friendshipState: .friends, isFollowing: true
    )

    static func cards(_ count: Int = 3, mode: DiscoveryModeV1 = .forYou) -> [DiscoveryCardV1] {
        (0..<count).map { index in
            let state: DiscoveryViewerRestaurantStateV1 = index == 1 ? .wantToGo : (index == 2 ? .visited : .none)
            let restaurant = DiscoveryRestaurantProjectionV1(
                globalKey: "place:preview-\(index)",
                placeIdentities: [.init(provider: .appleMaps, externalId: "apple-preview-\(index)", isPrimary: true)],
                name: index == 0 ? "山葵与炙烧寿司料理店" : "真实餐厅 \(index + 1)",
                address: "西湖区美食街 \(index + 1) 号", city: "杭州",
                latitude: 30.25, longitude: 120.16,
                tags: ["日料", "朋友聚餐"], pricePerPerson: 168,
                merchantImageUrl: index.isMultiple(of: 2) ? "https://images.unsplash.com/photo-1579871494447-9811cf80d66c" : nil,
                markerEmoji: index.isMultiple(of: 2) ? "🍣" : "🍲", photo: nil
            )
            let reason: DiscoveryReasonV1
            switch mode {
            case .forYou: reason = .init(code: index == 0 ? "FRIEND_HIGH_RATING" : "TASTE_TAG_MATCH",
                                         text: index == 0 ? "好友最近给过高分" : "符合你常给高分的日料口味")
            case .similarTaste: reason = .init(code: "SIMILAR_USERS", text: "基于 5 家共同评分餐厅，同味用户给过高分")
            case .trending: reason = .init(code: "TRENDING_UNIQUE_USERS", text: "近 7 天有 8 位用户到访")
            }
            return DiscoveryCardV1(
                id: "\(mode.rawValue):\(restaurant.globalKey)", mode: mode, restaurant: restaurant,
                viewerState: state,
                ratings: .init(
                    mine: .init(value: state == .visited ? 4.5 : nil, sampleCount: state == .visited ? 1 : 0),
                    community: .init(value: 4.6, sampleCount: 12),
                    friends: .init(value: index == 0 ? 5 : nil, sampleCount: index == 0 ? 2 : 0),
                    similarTaste: .init(value: mode == .similarTaste ? 4.8 : nil, sampleCount: mode == .similarTaste ? 4 : 0)
                ),
                reasons: [
                    reason,
                    .init(code: "COMMUNITY_QUALITY", text: "当前城市的公开评分样本稳定"),
                ], sourceUser: mode == .trending ? nil : user,
                activity: .init(
                    visitId: "preview-visit-\(index)",
                    visitedAt: "2026-08-30T12:00:00.000Z",
                    rating: index == 1 ? nil : 3.5
                ),
                similarity: mode == .similarTaste ? .init(percent: 91, sharedRestaurantCount: 5) : nil,
                trend: mode == .trending ? .init(windowDays: 7, uniqueVisitorCount: 8, wantToGoCount: 4) : nil,
                cacheScope: .public, rank: index + 1, score: Double(100 - index)
            )
        }
    }
}

#Preview("01 For You 正常") { DiscoveryPreviewHost(mode: .forYou, cards: DiscoveryPreviewFixtures.cards()) }
#Preview("02 For You 新用户") { DiscoveryPreviewHost(mode: .forYou, cards: [], message: "多记录几次，推荐会更懂你。") }
#Preview("03 Similar Taste 正常") { DiscoveryPreviewHost(mode: .similarTaste, cards: DiscoveryPreviewFixtures.cards(mode: .similarTaste)) }
#Preview("04 Similar Taste 数据不足") { DiscoveryPreviewHost(mode: .similarTaste, cards: [], message: "共同评分数据还不够，多记录几次后再来看看。") }
#Preview("05 Trending") { DiscoveryPreviewHost(mode: .trending, cards: DiscoveryPreviewFixtures.cards(mode: .trending)) }
#Preview("06 Offline cache") { DiscoveryPreviewHost(mode: .forYou, cards: DiscoveryPreviewFixtures.cards(), message: "当前显示上次缓存的内容。", cached: true) }
#Preview("07 Empty") { DiscoveryPreviewHost(mode: .forYou, cards: [], message: "这个城市暂时还没有可见的真实发现内容。") }
#Preview("08 Error") { DiscoveryPreviewHost(mode: .trending, cards: [], message: "发现内容暂时无法加载，请检查网络后重试。") }
#Preview("09 10+ Restaurant cards") { DiscoveryPreviewHost(mode: .forYou, cards: DiscoveryPreviewFixtures.cards(12)) }
#Preview("10 有图与无图混合") { DiscoveryPreviewHost(mode: .forYou, cards: DiscoveryPreviewFixtures.cards(6)) }
#Preview("11 好友推荐理由") { DiscoveryPreviewHost(mode: .forYou, cards: [DiscoveryPreviewFixtures.cards()[0]]) }
#Preview("12 同味推荐理由") { DiscoveryPreviewHost(mode: .similarTaste, cards: [DiscoveryPreviewFixtures.cards(mode: .similarTaste)[0]]) }
#Preview("13 已想吃") { DiscoveryPreviewHost(mode: .forYou, cards: [DiscoveryPreviewFixtures.cards()[1]]) }
#Preview("14 已去过") { DiscoveryPreviewHost(mode: .forYou, cards: [DiscoveryPreviewFixtures.cards()[2]]) }
#Preview("15 小屏") { DiscoveryPreviewHost(mode: .trending, cards: DiscoveryPreviewFixtures.cards(5, mode: .trending)).frame(width: 320) }
#Preview("16 大字体") { DiscoveryPreviewHost(mode: .forYou, cards: DiscoveryPreviewFixtures.cards()).environment(\.dynamicTypeSize, .accessibility3) }
