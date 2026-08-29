import SwiftData
import SwiftUI

struct RestaurantCollectionView: View {
    @Query private var restaurants: [Restaurant]
    @Query private var visits: [Visit]
    @Query private var photos: [PhotoAsset]

    let segment: RestaurantBrowseSegment
    @State private var selectedRestaurant: RestaurantBrowseSelection?
    @State private var query = ""

    var body: some View {
        let snapshot = RestaurantBrowseBuilder.build(
            restaurants: restaurants,
            visits: visits,
            photos: photos
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
            if let restaurant = restaurants.first(where: {
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

    private var filteredItems: [RestaurantBrowseItem] {
        RestaurantBrowseSearch.filter(items, query: query)
    }

    var body: some View {
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
                    description: Text("可以尝试搜索餐厅名称、城市或地址。")
                )
                .accessibilityIdentifier("restaurant-list-search-empty")
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredItems) { item in
                            RestaurantBrowseCard(item: item, segment: segment) {
                                onSelect(item)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
        .searchable(text: $query, prompt: "搜索餐厅、城市或地址")
    }
}

private struct RestaurantBrowseCard: View {
    let item: RestaurantBrowseItem
    let segment: RestaurantBrowseSegment
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                RestaurantBrowsePhoto(photo: item.photo, restaurantID: item.restaurant.id)
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.restaurant.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }

                    locationLine

                    if segment == .visited {
                        visitedSummary
                    } else if segment == .wantToGo {
                        Label(
                            "加入于 \(item.restaurant.createdAt.formatted(date: .abbreviated, time: .omitted))",
                            systemImage: "bookmark.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.16))
            }
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
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }

    private var visitedSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Label("\(item.visitCount) 次到访", systemImage: "clock.arrow.circlepath")
                if let averageRating = item.averageRating {
                    Label(String(format: "%.1f", averageRating), systemImage: "star.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption.weight(.medium))
            if let latestVisitAt = item.latestVisitAt {
                Text("最近到访 \(latestVisitAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("暂无有效到访记录")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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
                    colors: [Color.accentColor.opacity(0.16), Color(uiColor: .secondarySystemBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "fork.knife")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.75))
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
        ContentUnavailableView(
            segment.emptyTitle,
            systemImage: segment.systemImage,
            description: Text(segment.emptyMessage)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
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
