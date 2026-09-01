import SwiftData
import SwiftUI

struct RestaurantCollectionView: View {
    @Query private var restaurants: [Restaurant]
    @Query private var visits: [Visit]
    @Query private var photos: [PhotoAsset]
    @Query private var dishes: [Dish]
    @Query private var visitDishes: [VisitDish]
    @Query private var companions: [DiningCompanion]
    @Query private var recommendationSources: [RecommendationSource]

    let segment: RestaurantBrowseSegment
    let currentUserID: String?
    @State private var selectedRestaurant: RestaurantBrowseSelection?
    @State private var query = ""

    init(segment: RestaurantBrowseSegment, currentUserID: String? = nil) {
        self.segment = segment
        self.currentUserID = currentUserID
    }

    var body: some View {
        let owned = ProfileOwnedContentScope.capture(
            currentUserID: currentUserID,
            restaurants: restaurants,
            visits: visits,
            photos: photos,
            dishes: dishes,
            visitDishes: visitDishes,
            companions: companions,
            recommendationSources: recommendationSources
        )
        let snapshot = RestaurantBrowseBuilder.build(
            restaurants: owned.restaurants,
            visits: owned.visits,
            photos: owned.photos,
            dishes: owned.dishes,
            visitDishes: owned.visitDishes,
            companions: owned.companions,
            recommendationSources: owned.recommendationSources
        )
        RestaurantBrowseList(
            segment: segment,
            items: snapshot.items(for: segment),
            query: $query,
            isFiltered: false,
            onClearFilters: {},
            onSelect: { selectedRestaurant = RestaurantBrowseSelection(id: $0.restaurant.id) }
        )
        .navigationTitle(segment == .visited ? "去过的餐厅" : segment == .wantToGo ? "想吃的餐厅" : segment.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedRestaurant) { selection in
            if let restaurant = owned.restaurants.first(where: {
                $0.id == selection.id && $0.deletedAt == nil
            }) {
                RestaurantDetailView(restaurant: restaurant, entrySource: .list)
            } else {
                TasteMapEmptyState(
                    title: "餐厅不存在",
                    message: "这家餐厅可能已经被删除或尚未同步完成。",
                    systemImage: "fork.knife",
                    presentation: .embedded
                )
            }
        }
    }
}

struct RestaurantBrowseList: View {
    let segment: RestaurantBrowseSegment
    let items: [RestaurantBrowseItem]
    @Binding var query: String
    let isFiltered: Bool
    let onClearFilters: () -> Void
    let onSelect: (RestaurantBrowseItem) -> Void
    var onRecordVisit: ((RestaurantBrowseItem) -> Void)?
    var onToggleWantToGo: ((RestaurantBrowseItem) -> Void)?
    var onOpenRoulette: ((RestaurantBrowseItem) -> Void)?
    var usesSystemSearch = true
    var showsContextHeader = false
    var contentTopInset: CGFloat = 0
    var contentBottomInset: CGFloat = 28

    private var filteredItems: [RestaurantBrowseItem] {
        RestaurantBrowseSearch.filter(items, query: query)
    }

    var body: some View {
        if usesSystemSearch {
            content
                .searchable(text: $query, prompt: "搜索餐厅、城市、饭搭子或菜品")
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if items.isEmpty, isFiltered {
                TasteMapEmptyState(
                    title: "当前无符合条件的餐厅",
                    message: "可以清除筛选，重新查看你的餐厅。",
                    systemImage: "line.3.horizontal.decrease.circle",
                    actionTitle: "清除全部筛选",
                    action: onClearFilters,
                    actionAccessibilityIdentifier: "personal-filter-list-zero-clear",
                    presentation: .embedded,
                    accessibilityIdentifier: "personal-filter-list-zero"
                )
                .accessibilityIdentifier("personal-filter-list-zero")
            } else if items.isEmpty {
                RestaurantBrowseEmptyState(segment: segment)
            } else if filteredItems.isEmpty {
                TasteMapEmptyState(
                    title: "没有找到匹配的餐厅",
                    message: "可以尝试搜索餐厅、城市、备注、饭搭子或菜品。",
                    systemImage: "magnifyingglass",
                    presentation: .embedded,
                    accessibilityIdentifier: "restaurant-list-search-empty"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if showsContextHeader {
                            RestaurantBrowseListContext(
                                segment: segment,
                                resultCount: filteredItems.count,
                                isFiltered: isFiltered,
                                hasQuery: !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                        }
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            RestaurantBrowseCard(
                                item: item,
                                segment: segment,
                                onSelect: { onSelect(item) },
                                onRecordVisit: onRecordVisit.map { action in { action(item) } },
                                onToggleWantToGo: onToggleWantToGo.map { action in { action(item) } },
                                onOpenRoulette: onOpenRoulette.map { action in { action(item) } }
                            )
                            if index < filteredItems.count - 1 {
                                Divider().padding(.leading, 66)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, contentBottomInset)
                }
                .background(TasteMapCoreTheme.page)
            }
        }
        .padding(.top, contentTopInset)
    }
}

private struct RestaurantBrowseListContext: View {
    let segment: RestaurantBrowseSegment
    let resultCount: Int
    let isFiltered: Bool
    let hasQuery: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MY TASTE MAP")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(TasteMapCoreTheme.brand)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TasteMapCoreTheme.textPrimary)
            }
            Spacer(minLength: 8)
            Text("\(resultCount) 家")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TasteMapCoreTheme.textSecondary)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(TasteMapCoreTheme.surfaceSubtle, in: Capsule())
                .accessibilityIdentifier("restaurant-list-result-count")
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("restaurant-list-context")
    }

    private var title: String {
        let base: String
        switch segment {
        case .visited: base = "去过的餐厅"
        case .wantToGo: base = "想吃的餐厅"
        case .forYou: base = "推荐餐厅"
        }
        if hasQuery { return "\(base) · 搜索结果" }
        if isFiltered { return "\(base) · 已筛选" }
        return base
    }
}

private struct RestaurantBrowseCard: View {
    let item: RestaurantBrowseItem
    let segment: RestaurantBrowseSegment
    let onSelect: () -> Void
    let onRecordVisit: (() -> Void)?
    let onToggleWantToGo: (() -> Void)?
    let onOpenRoulette: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            RestaurantBrowsePhoto(
                photo: item.photo,
                publicPhotoID: item.publicPhotoID,
                merchantImageURL: item.merchantImageURL,
                restaurantID: item.restaurant.id
            )
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                Button(action: onSelect) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(item.restaurant.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(TasteMapCoreTheme.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }

                        if segment == .visited {
                            visitedSummary
                        } else if segment == .wantToGo {
                            Label(
                                "加入于 \(TasteMapDisplayDate.abbreviatedDate(item.restaurant.createdAt))",
                                systemImage: "bookmark.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(TasteMapCoreTheme.brand)
                        }

                        locationLine
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("restaurant-list-item-\(item.restaurant.id.uuidString)")

                if hasQuickActions {
                    HStack(spacing: 5) {
                        if let onRecordVisit {
                            quickAction(
                                title: item.visitCount > 0 ? "再次记录" : "记录到访",
                                systemImage: "plus.circle.fill",
                                identifier: "restaurant-list-record-\(item.restaurant.id.uuidString)",
                                action: onRecordVisit
                            )
                        }
                        if let onToggleWantToGo {
                            quickAction(
                                title: item.restaurant.status == .wantToGo ? "移出想吃" : "想吃",
                                systemImage: item.restaurant.status == .wantToGo ? "bookmark.fill" : "bookmark",
                                identifier: "restaurant-list-want-\(item.restaurant.id.uuidString)",
                                isSelected: item.restaurant.status == .wantToGo,
                                action: onToggleWantToGo
                            )
                        }
                        if let onOpenRoulette {
                            quickAction(
                                title: "今天吃",
                                systemImage: "dice",
                                identifier: "restaurant-list-roulette-\(item.restaurant.id.uuidString)",
                                action: onOpenRoulette
                            )
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("\(item.restaurant.name) 快捷操作")
                    .accessibilityIdentifier("restaurant-list-actions-\(item.restaurant.id.uuidString)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("restaurant-list-row-\(item.restaurant.id.uuidString)")
    }

    private var hasQuickActions: Bool {
        onRecordVisit != nil || onToggleWantToGo != nil || onOpenRoulette != nil
    }

    private func quickAction(
        title: String,
        systemImage: String,
        identifier: String,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(isSelected ? TasteMapCoreTheme.brand : TasteMapCoreTheme.textSecondary)
                .padding(.horizontal, 8)
                .frame(minHeight: 28)
                .background(
                    isSelected ? TasteMapCoreTheme.brandSoft : TasteMapCoreTheme.surfaceSubtle,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var locationLine: some View {
        let location = [item.restaurant.city, item.restaurant.address]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " · ")
        if !location.isEmpty {
            Label(location, systemImage: "mappin.and.ellipse")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .multilineTextAlignment(.leading)
        }
    }

    private var visitedSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Label("\(item.visitCount) 次到访", systemImage: "clock.arrow.circlepath")
                if let averageRating = item.averageRating {
                    Label(String(format: "%.1f", averageRating), systemImage: "star.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption2.weight(.medium))
        }
    }
}

struct RestaurantBrowsePhoto: View {
    let photo: PhotoAsset?
    var publicPhotoID: String? = nil
    let merchantImageURL: URL?
    let restaurantID: UUID

    var body: some View {
        TasteMapRestaurantImage(
            resolution: RestaurantImagePriorityPolicy.resolution(
                localUserPhotoID: photo?.id,
                publicOrCachedPhotoID: publicPhotoID,
                providerMerchantImageURL: merchantImageURL
            ),
            photosByID: photo.map { [$0.id: $0] } ?? [:],
            semanticID: restaurantID.uuidString,
            fallbackBackgroundColor: TasteMapCoreTheme.brandSoft,
            fallbackIconSize: 38,
            accessibilityLabel: "餐厅图片"
        )
    }
}

struct RestaurantBrowseEmptyState: View {
    let segment: RestaurantBrowseSegment

    var body: some View {
        TasteMapEmptyState(
            title: segment.emptyTitle,
            message: segment.emptyMessage,
            systemImage: segment.systemImage
        )
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TasteMapCoreTheme.page)
        .accessibilityIdentifier("restaurant-list-empty-\(segment.rawValue)")
    }
}

struct RestaurantBrowseSelection: Identifiable {
    let id: UUID
}

#Preview("去过列表") {
    let container = try! TasteMapPersistence.makeContainer(inMemory: true)
    let restaurant = Restaurant(
        name: "这是一家名称很长但仍然需要保持清晰可读的江南小馆",
        address: "文三路 88 号",
        latitude: 30.2,
        longitude: 120.1,
        city: "杭州",
        status: .visited,
        createdAt: .now.addingTimeInterval(-86_400 * 20)
    )
    container.mainContext.insert(restaurant)
    container.mainContext.insert(Visit(
        restaurantId: restaurant.id,
        visitedAt: .now.addingTimeInterval(-86_400),
        rating: 4.5
    ))
    return NavigationStack { RestaurantCollectionView(segment: .visited) }
        .modelContainer(container)
}

#Preview("想吃空状态") {
    let container = try! TasteMapPersistence.makeContainer(inMemory: true)
    return NavigationStack { RestaurantCollectionView(segment: .wantToGo) }
        .modelContainer(container)
}
