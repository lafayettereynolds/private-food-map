#if DEBUG
import SwiftData
import SwiftUI

@MainActor
private enum RestaurantListPreviewScenario {
    case empty
    case overview(listCount: Int, longTitle: Bool = false)
    case detail(itemCount: Int, ranked: Bool, visibility: RestaurantListVisibility, longRestaurantName: Bool = false)

    var container: ModelContainer {
        let container = try! TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let store = LocalRestaurantListStore(context: context)
        switch self {
        case .empty:
            break
        case .overview(let listCount, let longTitle):
            for index in 0..<listCount {
                let list = try! store.create(
                    ownerUserID: "tm_preview",
                    title: longTitle && index == 0
                        ? "杭州下雨天也愿意专程穿过半座城去吃的温暖小馆与深夜食堂"
                        : ["最喜欢的火锅", "适合约会", "今年的新店", "朋友来杭州带他们吃"][index % 4],
                    description: index == 0 ? "按自己的味觉与真实到访整理，不代表官方排名。" : "",
                    visibility: RestaurantListVisibility.allCases[index % 3],
                    isRanked: index.isMultiple(of: 2)
                )
                if index == 0 {
                    for place in places(count: 3, longName: false) {
                        _ = try! store.add(candidate: place, to: list, actorUserID: "tm_preview")
                    }
                }
            }
        case .detail(let itemCount, let ranked, let visibility, let longRestaurantName):
            let list = try! store.create(
                ownerUserID: "tm_preview",
                title: ranked ? "杭州日料 Top (max(3, min(itemCount, 10)))" : "想带朋友去",
                description: "从真实吃过与发现的餐厅里慢慢整理，顺序由我自己决定。",
                visibility: visibility,
                isRanked: ranked
            )
            for (index, place) in places(count: itemCount, longName: longRestaurantName).enumerated() {
                let item = try! store.add(candidate: place, to: list, actorUserID: "tm_preview")
                if index == 0 { try! store.updateNote(item, note: "一定要点招牌菜，晚餐建议提前到。", actorUserID: "tm_preview") }
            }
        }
        return container
    }

    private func places(count: Int, longName: Bool) -> [RestaurantCandidate] {
        (0..<count).map { index in
            RestaurantCandidate(
                name: longName && index == 0
                    ? "山野季节料理与手作发酵实验室西湖边特别限定店"
                    : ["青岚寿司", "雨巷火锅", "野火烧鸟", "小满食堂", "南山牛排"][index % 5] + " (index + 1)",
                address: "杭州市西湖区味觉路 (index + 1) 号",
                latitude: 30.20 + Double(index) * 0.001,
                longitude: 120.10 + Double(index) * 0.001,
                appleMapItemIdentifier: "p4f-preview-\(index)"
            )
        }
    }
}

private struct RestaurantListOverviewPreviewHost: View {
    let scenario: RestaurantListPreviewScenario
    var body: some View {
        NavigationStack {
            RestaurantListsOverviewView(currentUserID: "tm_preview", photoAPI: nil)
        }
        .modelContainer(scenario.container)
    }
}

private struct RestaurantListDetailPreviewHost: View {
    @Query private var lists: [RestaurantList]
    let scenario: RestaurantListPreviewScenario

    var body: some View {
        NavigationStack {
            if let list = lists.first {
                RestaurantListDetailView(list: list, currentUserID: "tm_preview", photoAPI: nil)
            } else {
                ContentUnavailableView("没有预览榜单", systemImage: "list.number")
            }
        }
        .modelContainer(scenario.container)
    }
}

private struct PublicRestaurantListPreviewHost: View {
    private let api = RestaurantListPreviewAPI()
    var body: some View {
        PublicRestaurantListDetailView(
            summary: api.summary,
            currentUserID: "tm_viewer",
            api: api,
            photoAPI: nil
        )
        .modelContainer(try! TasteMapPersistence.makeContainer(inMemory: true))
    }
}

@MainActor
private final class RestaurantListPreviewAPI: RestaurantListAPI {
    let summary = PublicListSummaryDTO(
        id: "p4f-public-preview", title: "阿岚的杭州小馆", description: "适合慢慢吃、愿意再去的小店。",
        visibility: .public, isRanked: true, coverMode: .automatic,
        customCoverPhotoId: nil, restaurantCount: 3,
        previewRestaurants: [
            .init(globalKey: "apple_maps:public-1", name: "云边小馆", photoId: nil, merchantImageUrl: nil, markerEmoji: "🍲"),
            .init(globalKey: "apple_maps:public-2", name: "野火烧鸟", photoId: nil, merchantImageUrl: nil, markerEmoji: "🍢"),
            .init(globalKey: "apple_maps:public-3", name: "青岚寿司", photoId: nil, merchantImageUrl: nil, markerEmoji: "🍣"),
        ],
        owner: .init(userId: "tm_owner", displayName: "常去小馆的阿岚", avatarPhotoId: nil, avatarPresetId: .otter),
        updatedAt: "2026-08-28T12:00:00.000Z"
    )

    func profileLists(userID: String, cursor: String?, limit: Int) async throws -> PublicListSummaryPageDTO {
        .init(apiVersion: 1, items: [summary], nextCursor: nil, generatedAt: summary.updatedAt)
    }

    func detail(listID: String, cursor: String?, limit: Int) async throws -> PublicListDetailDTO {
        let items = try (0..<3).map { index in
            PublicListItemDTO(
                id: "public-item-\(index)", position: index,
                note: index == 0 ? "招牌菜值得专程来。" : "",
                restaurant: try RestaurantListPlaceContractV1(
                    globalKey: "apple_maps:public-\(index + 1)",
                    restaurantId: "public-restaurant-\(index)",
                    placeIdentities: [.init(provider: .appleMaps, externalId: "public-\(index + 1)", isPrimary: true)],
                    name: ["云边小馆", "野火烧鸟", "青岚寿司"][index],
                    address: "杭州市西湖区公开路 \(index + 1) 号", city: "杭州",
                    latitude: 30.25, longitude: 120.16,
                    markerPhotoId: nil, merchantImageUrl: nil,
                    markerEmoji: ["🍲", "🍢", "🍣"][index]
                )
            )
        }
        return .init(apiVersion: 1, list: summary, items: items, nextCursor: nil, generatedAt: summary.updatedAt)
    }
}

#Preview("01 无榜单") { RestaurantListOverviewPreviewHost(scenario: .empty) }
#Preview("02 单个榜单") { RestaurantListOverviewPreviewHost(scenario: .overview(listCount: 1)) }
#Preview("03 多榜单") { RestaurantListOverviewPreviewHost(scenario: .overview(listCount: 6)) }
#Preview("04 空榜单") { RestaurantListDetailPreviewHost(scenario: .detail(itemCount: 0, ranked: false, visibility: .private)) }
#Preview("05 三家餐厅") { RestaurantListDetailPreviewHost(scenario: .detail(itemCount: 3, ranked: false, visibility: .private)) }
#Preview("06 十家餐厅") { RestaurantListDetailPreviewHost(scenario: .detail(itemCount: 10, ranked: true, visibility: .public)) }
#Preview("07 五十家以上") { RestaurantListDetailPreviewHost(scenario: .detail(itemCount: 54, ranked: true, visibility: .private)) }
#Preview("08 Top 3") { RestaurantListDetailPreviewHost(scenario: .detail(itemCount: 3, ranked: true, visibility: .public)) }
#Preview("09 无照片") { RestaurantListDetailPreviewHost(scenario: .detail(itemCount: 5, ranked: false, visibility: .private)) }
#Preview("10 长餐厅名") { RestaurantListDetailPreviewHost(scenario: .detail(itemCount: 5, ranked: true, visibility: .private, longRestaurantName: true)) }
#Preview("11 长榜单标题") { RestaurantListOverviewPreviewHost(scenario: .overview(listCount: 2, longTitle: true)) }
#Preview("12 公开榜单") { PublicRestaurantListPreviewHost() }
#Preview("13 私密榜单 Owner") { RestaurantListDetailPreviewHost(scenario: .detail(itemCount: 5, ranked: false, visibility: .private)) }
#Preview("14 好友可见") { RestaurantListDetailPreviewHost(scenario: .detail(itemCount: 5, ranked: true, visibility: .friends)) }
#Preview("15 排序编辑") { RestaurantListDetailPreviewHost(scenario: .detail(itemCount: 8, ranked: true, visibility: .private)) }
#Preview("16 小屏幕") {
    RestaurantListDetailPreviewHost(scenario: .detail(itemCount: 6, ranked: true, visibility: .public))
        .frame(width: 320, height: 568)
}
#Preview("17 大字体") {
    RestaurantListDetailPreviewHost(scenario: .detail(itemCount: 5, ranked: true, visibility: .friends))
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
