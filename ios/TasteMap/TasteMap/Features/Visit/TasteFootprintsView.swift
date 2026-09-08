import SwiftData
import SwiftUI

private enum TasteFootprintTimelineItem: Identifiable {
    case visit(TasteFootprintItem)
    case wantToGo(RestaurantBrowseItem)

    var id: String {
        switch self {
        case let .visit(item): "visit-\(item.visit.id.uuidString)"
        case let .wantToGo(item): "want-to-go-\(item.restaurant.id.uuidString)"
        }
    }

    var eventAt: Date {
        switch self {
        case let .visit(item): item.visit.visitedAt
        case let .wantToGo(item): item.restaurant.createdAt
        }
    }

    var restaurant: Restaurant {
        switch self {
        case let .visit(item): item.restaurant
        case let .wantToGo(item): item.restaurant
        }
    }
}

struct TasteFootprintsView: View {
    @Query private var restaurants: [Restaurant]
    @Query private var visits: [Visit]
    @Query private var photos: [PhotoAsset]
    @Query private var dishes: [Dish]
    @Query private var visitDishes: [VisitDish]
    @Query private var companions: [DiningCompanion]
    @Query private var recommendationSources: [RecommendationSource]

    @State private var selectedRestaurant: RestaurantBrowseSelection?
    let currentUserID: String?

    init(currentUserID: String? = nil) {
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
        let timelineItems = (
            snapshot.footprints.map(TasteFootprintTimelineItem.visit)
                + snapshot.wantToGo.map(TasteFootprintTimelineItem.wantToGo)
        ).sorted {
            if $0.eventAt != $1.eventAt { return $0.eventAt > $1.eventAt }
            return $0.id < $1.id
        }

        Group {
            if timelineItems.isEmpty {
                TasteMapEmptyState(
                    title: "还没有味觉足迹",
                    message: "每次真实到访与想去收藏都会在这里留下记录，包括未评分的到访。",
                    systemImage: "point.bottomleft.forward.to.point.topright.scurvepath",
                    foodDiningVisualKind: .location,
                    presentation: .embedded,
                    accessibilityIdentifier: "taste-footprints-empty"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(timelineItems.enumerated()), id: \.element.id) { index, item in
                            switch item {
                            case let .visit(visitItem):
                                TasteFootprintRow(
                                    item: visitItem,
                                    showsTopLine: index > 0,
                                    showsBottomLine: index < timelineItems.count - 1,
                                    onSelect: {
                                        selectedRestaurant = RestaurantBrowseSelection(id: item.restaurant.id)
                                    }
                                )
                            case let .wantToGo(wantItem):
                                WantToGoFootprintRow(
                                    item: wantItem,
                                    showsTopLine: index > 0,
                                    showsBottomLine: index < timelineItems.count - 1,
                                    onSelect: {
                                        selectedRestaurant = RestaurantBrowseSelection(id: item.restaurant.id)
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
                .background(TasteMapCoreTheme.page)
            }
        }
        .navigationTitle("味觉足迹")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedRestaurant) { selection in
            if let restaurant = owned.restaurants.first(where: {
                $0.id == selection.id && $0.deletedAt == nil
            }) {
                RestaurantDetailView(restaurant: restaurant, entrySource: .analysis)
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

private struct TasteFootprintRow: View {
    let item: TasteFootprintItem
    let showsTopLine: Bool
    let showsBottomLine: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 11) {
                    header
                    RestaurantBrowsePhoto(
                        photo: item.photo,
                        publicPhotoID: item.publicPhotoID,
                        merchantImageURL: item.merchantImageURL,
                        restaurantID: item.restaurant.id,
                        restaurantName: item.restaurant.name,
                        categoryTags: item.restaurant.remoteRecordData.flatMap {
                            try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0)
                        }?.tags ?? []
                    )
                        .frame(width: TasteMapDesignTokens.Layout.socialFeedMediaWidth, height: TasteMapDesignTokens.Layout.socialFeedMediaWidth)
                        .clipShape(RoundedRectangle(cornerRadius: TasteMapDesignTokens.Radius.compact, style: .continuous))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let note = item.visit.note, !note.isEmpty {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                    }
                    metadata
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, TasteMapDesignTokens.Spacing.content)
                .overlay(alignment: .bottom) { Divider() }
                .padding(.bottom, 14)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("taste-footprint-item-\(item.visit.id.uuidString)")
        }
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(showsTopLine ? Color.accentColor.opacity(0.22) : .clear)
                .frame(width: 2, height: 13)
            Circle()
                .fill(Color.accentColor)
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(.background, lineWidth: 3))
                .shadow(color: Color.accentColor.opacity(0.2), radius: 3)
            Rectangle()
                .fill(showsBottomLine ? Color.accentColor.opacity(0.22) : .clear)
                .frame(width: 2)
        }
        .frame(width: 14)
        .accessibilityHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.restaurant.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 6)
                TasteMapActivityRatingBadge(rating: item.visit.rating)
            }
            Text(TasteMapDisplayDate.abbreviatedDateTime(item.visit.visitedAt))
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentColor)
            let location = [item.restaurant.city, item.restaurant.address]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " · ")
            if !location.isEmpty {
                Text(location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    @ViewBuilder
    private var metadata: some View {
        let dishes = item.dishNames.prefix(3).joined(separator: "、")
        let companions = item.companionNames.prefix(3).joined(separator: "、")
        if !dishes.isEmpty || !companions.isEmpty || item.recommendationSource != nil {
            VStack(alignment: .leading, spacing: 6) {
                if !dishes.isEmpty {
                    Label(dishes, systemImage: "takeoutbag.and.cup.and.straw")
                }
                if !companions.isEmpty {
                    Label(companions, systemImage: "person.2")
                }
                if let source = item.recommendationSource {
                    Label(source, systemImage: "lightbulb")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct WantToGoFootprintRow: View {
    let item: RestaurantBrowseItem
    let showsTopLine: Bool
    let showsBottomLine: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(alignment: .firstTextBaseline) {
                        Label("加入想吃", systemImage: "bookmark.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                        Spacer(minLength: 8)
                        Text(TasteMapDisplayDate.abbreviatedDateTime(item.restaurant.createdAt))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.restaurant.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    RestaurantBrowsePhoto(
                        photo: item.photo,
                        publicPhotoID: item.publicPhotoID,
                        merchantImageURL: item.merchantImageURL,
                        restaurantID: item.restaurant.id,
                        restaurantName: item.restaurant.name,
                        categoryTags: item.restaurantTags.sorted()
                    )
                    .frame(width: TasteMapDesignTokens.Layout.socialFeedMediaWidth, height: TasteMapDesignTokens.Layout.socialFeedMediaWidth)
                    .clipShape(RoundedRectangle(cornerRadius: TasteMapDesignTokens.Radius.compact, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    let location = [item.restaurant.city, item.restaurant.address]
                        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        .joined(separator: " · ")
                    if !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Text("先收藏起来，留给下一次出发。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, TasteMapDesignTokens.Spacing.content)
                .overlay(alignment: .bottom) { Divider() }
                .padding(.bottom, 14)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("taste-footprint-want-to-go-\(item.restaurant.id.uuidString)")
        }
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(showsTopLine ? Color.accentColor.opacity(0.22) : .clear)
                .frame(width: 2, height: 13)
            Circle()
                .fill(Color.accentColor.opacity(0.88))
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(.background, lineWidth: 3))
                .shadow(color: Color.accentColor.opacity(0.2), radius: 3)
            Rectangle()
                .fill(showsBottomLine ? Color.accentColor.opacity(0.22) : .clear)
                .frame(width: 2)
        }
        .frame(width: 14)
        .accessibilityHidden(true)
    }
}

#Preview("味觉足迹 · 多次到访") {
    let container = try! TasteMapPersistence.makeContainer(inMemory: true)
    let restaurant = Restaurant(
        name: "山葵小料理",
        address: "湖滨路 18 号",
        latitude: 30.2,
        longitude: 120.1,
        city: "杭州",
        status: .visited
    )
    container.mainContext.insert(restaurant)
    container.mainContext.insert(Visit(
        restaurantId: restaurant.id,
        visitedAt: .now.addingTimeInterval(-3_600),
        rating: 4.5,
        note: "今天的季节菜单很轻盈，最喜欢最后一道甜品。",
        companionNames: ["小林"],
        recommendationSourceType: .friend
    ))
    container.mainContext.insert(Visit(
        restaurantId: restaurant.id,
        visitedAt: .now.addingTimeInterval(-86_400 * 20),
        rating: nil
    ))
    return NavigationStack { TasteFootprintsView() }.modelContainer(container)
}

#Preview("味觉足迹 · 空状态") {
    let container = try! TasteMapPersistence.makeContainer(inMemory: true)
    return NavigationStack { TasteFootprintsView() }.modelContainer(container)
}
