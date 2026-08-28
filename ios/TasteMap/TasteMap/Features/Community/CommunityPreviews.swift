#if DEBUG
import SwiftUI

private struct CommunityPreviewStateView: View {
    let title: String
    let message: String?
    let items: [PublicContentItemV1]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if let message {
                        Label(message, systemImage: message.contains("离线") ? "wifi.slash" : "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if items.isEmpty {
                        ContentUnavailableView(
                            "暂时没有可见内容", systemImage: "fork.knife.circle",
                            description: Text("只有用户允许展示的记录才会出现在这里。")
                        ).frame(minHeight: 420)
                    }
                    ForEach(items) { item in
                        PublicContentCard(
                            item: item, photoAPI: nil,
                            onOpenRestaurant: {}, onOpenUser: {}, onWantToGo: {}
                        )
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(title)
        }
    }
}

@MainActor
private enum CommunityPreviewData {
    static let publicItems = makeItems(count: 4)
    static let friendItem = makeItem(index: 8, scope: .friends, longName: false, longNote: false, photoCount: 1)
    static let noPhoto = makeItem(index: 9, scope: .public, longName: false, longNote: false, photoCount: 0)
    static let multiPhoto = makeItem(index: 10, scope: .public, longName: false, longNote: false, photoCount: 3)
    static let longText = makeItem(index: 11, scope: .public, longName: true, longNote: true, photoCount: 1)
    static let wants = PublicContentItemV1(
        id: "want-preview", kind: .wantToGo, eventAt: "2026-08-28T10:00:00.000Z",
        updatedAt: "2026-08-28T10:00:00.000Z",
        user: user(index: 12), restaurant: restaurant(index: 12, photoCount: 0), visit: nil,
        viewerState: .none, cacheScope: .public
    )

    static func makeItems(count: Int) -> [PublicContentItemV1] {
        (0..<count).map { makeItem(index: $0, scope: .public, longName: false, longNote: false, photoCount: $0 % 4) }
    }

    static func makeItem(
        index: Int,
        scope: PublicContentCacheScopeV1,
        longName: Bool,
        longNote: Bool,
        photoCount: Int
    ) -> PublicContentItemV1 {
        let owner = user(index: index, longName: longName, friend: scope == .friends)
        let place = restaurant(index: index, photoCount: photoCount)
        let photos = (0..<photoCount).map { photoIndex in
            PublicContentPhotoV1(
                photoId: String(format: "00000000-0000-4000-8000-%012d", index * 10 + photoIndex),
                variant: .thumbnail
            )
        }
        return PublicContentItemV1(
            id: "preview-\(index)", kind: .visit,
            eventAt: "2026-08-28T\(String(format: "%02d", max(0, 18 - index))):00:00.000Z",
            updatedAt: "2026-08-28T18:00:00.000Z", user: owner, restaurant: place,
            visit: .init(
                id: "visit-preview-\(index)", ownerUserId: owner.userId,
                restaurantGlobalKey: place.globalKey, visitedAt: "2026-08-28T12:00:00.000Z",
                rating: index.isMultiple(of: 3) ? nil : 4.5,
                note: longNote
                    ? "这是一段很长的公开到访记录，用于检查长文字在大字体和小屏幕上是否仍然自然可读。它只描述可公开的餐厅体验，不包含消费、饭搭子、推荐来源或任何私密身份信息。"
                    : "锅气很足，味道稳定，是会想再来的一家店。",
                visibility: scope == .friends ? .friends : .public, photos: photos,
                updatedAt: "2026-08-28T18:00:00.000Z"
            ),
            viewerState: index.isMultiple(of: 5) ? .visited : .none, cacheScope: scope
        )
    }

    static func user(index: Int, longName: Bool = false, friend: Bool = false) -> PublicContentUserV1 {
        .init(
            userId: "tm_preview_\(index)",
            displayName: longName ? "一位名字特别长但依然认真记录每顿饭的用户" : "探店用户 \(index + 1)",
            bio: "认真记录每一次好好吃饭。", city: "杭州", avatarPhotoId: nil,
            avatarPresetId: index.isMultiple(of: 2) ? .otter : .penguin,
            friendshipId: friend ? "friend-preview" : nil,
            friendshipState: friend ? .friends : .none, isFollowing: index.isMultiple(of: 2)
        )
    }

    static func restaurant(index: Int, photoCount: Int) -> PublicContentRestaurantV1 {
        let photo = photoCount == 0 ? nil : PublicContentPhotoV1(
            photoId: String(format: "00000000-0000-4000-8000-%012d", index * 10), variant: .thumbnail
        )
        return .init(
            globalKey: "place:preview-\(index)",
            placeIdentities: [.init(provider: .appleMaps, externalId: "apple-preview-\(index)", isPrimary: true)],
            name: index.isMultiple(of: 2) ? "云边小馆·湖滨店" : "一间值得再次到访的社区餐厅",
            address: "湖滨路 \(index + 1) 号", city: "杭州", latitude: 30.25, longitude: 120.16,
            tags: ["本帮菜", "朋友聚餐"], pricePerPerson: 136, merchantImageUrl: nil,
            markerEmoji: index.isMultiple(of: 2) ? "🍲" : "🍣", photo: photo
        )
    }
}

#Preview("01 Community Feed 正常") { CommunityPreviewStateView(title: "社区", message: nil, items: CommunityPreviewData.publicItems) }
#Preview("02 Public Profile Content") { CommunityPreviewStateView(title: "公开主页", message: nil, items: CommunityPreviewData.publicItems) }
#Preview("03 Public Visit") { CommunityPreviewStateView(title: "公开记录", message: nil, items: [CommunityPreviewData.publicItems[0]]) }
#Preview("04 Friends Visit 好友可见") { CommunityPreviewStateView(title: "好友内容", message: nil, items: [CommunityPreviewData.friendItem]) }
#Preview("05 Non-friend Hidden") { CommunityPreviewStateView(title: "公开主页", message: nil, items: []) }
#Preview("06 Multiple Photos") { CommunityPreviewStateView(title: "多图动态", message: nil, items: [CommunityPreviewData.multiPhoto]) }
#Preview("07 No Photo") { CommunityPreviewStateView(title: "无图片", message: nil, items: [CommunityPreviewData.noPhoto]) }
#Preview("08 Cached Offline") { CommunityPreviewStateView(title: "社区", message: "离线显示最近缓存的公开内容", items: CommunityPreviewData.publicItems) }
#Preview("09 Error") { CommunityPreviewStateView(title: "社区", message: "社区内容暂时无法加载，请稍后重试。", items: []) }
#Preview("10 Empty Following") { CommunityPreviewStateView(title: "关注", message: nil, items: []) }
#Preview("11 Empty Latest") { CommunityPreviewStateView(title: "最新", message: nil, items: []) }
#Preview("12 Long Note") { CommunityPreviewStateView(title: "长备注", message: nil, items: [CommunityPreviewData.longText]) }
#Preview("13 Long User Name") { CommunityPreviewStateView(title: "长用户名", message: nil, items: [CommunityPreviewData.longText]) }
#Preview("14 Twenty Plus Items") { CommunityPreviewStateView(title: "分页长列表", message: nil, items: CommunityPreviewData.makeItems(count: 22)) }
#Preview("15 Want To Go Content") { CommunityPreviewStateView(title: "想吃餐厅", message: nil, items: [CommunityPreviewData.wants]) }
#Preview("16 Small Screen") { CommunityPreviewStateView(title: "社区", message: nil, items: CommunityPreviewData.publicItems).frame(width: 320, height: 568) }
#Preview("17 Large Font") { CommunityPreviewStateView(title: "社区", message: nil, items: [CommunityPreviewData.longText]).environment(\.dynamicTypeSize, .accessibility3) }
#endif
