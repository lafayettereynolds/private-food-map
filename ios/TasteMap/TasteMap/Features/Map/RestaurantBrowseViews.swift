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
                RestaurantDetailView(restaurant: restaurant)
            } else {
                ContentUnavailableView("餐厅不存在", systemImage: "fork.knife")
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
    var usesSystemSearch = true
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
                ContentUnavailableView {
                    Label("当前无符合条件的餐厅", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("可以清除筛选，重新查看你的餐厅。")
                } actions: {
                    Button("清除全部筛选", action: onClearFilters)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("personal-filter-list-zero-clear")
                }
                .accessibilityIdentifier("personal-filter-list-zero")
            } else if items.isEmpty {
                RestaurantBrowseEmptyState(segment: segment)
            } else if filteredItems.isEmpty {
                ContentUnavailableView(
                    "没有找到匹配的餐厅",
                    systemImage: "magnifyingglass",
                    description: Text("可以尝试搜索餐厅、城市、备注、饭搭子或菜品。")
                )
                .accessibilityIdentifier("restaurant-list-search-empty")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            RestaurantBrowseCard(item: item, segment: segment) {
                                onSelect(item)
                            }
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

private struct RestaurantBrowseCard: View {
    let item: RestaurantBrowseItem
    let segment: RestaurantBrowseSegment
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                RestaurantBrowsePhoto(photo: item.photo, restaurantID: item.restaurant.id)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

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
                            "加入于 \(item.restaurant.createdAt.formatted(date: .abbreviated, time: .omitted))",
                            systemImage: "bookmark.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(TasteMapCoreTheme.brand)
                    }

                    locationLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("restaurant-list-item-\(item.restaurant.id.uuidString)")
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
    let restaurantID: UUID

    var body: some View {
        if let photo {
            PhotoAssetImageView(photo: photo, variant: .thumbnail)
        } else {
            ZStack {
                LinearGradient(
                    colors: [TasteMapCoreTheme.brandSoft, TasteMapCoreTheme.surfaceSubtle],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "fork.knife")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(TasteMapCoreTheme.brand.opacity(0.82))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("餐厅暂无照片")
            .accessibilityIdentifier("restaurant-photo-fallback-\(restaurantID.uuidString)")
        }
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
