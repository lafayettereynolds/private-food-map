import SwiftData
import SwiftUI

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

        Group {
            if snapshot.footprints.isEmpty {
                ContentUnavailableView(
                    "还没有味觉足迹",
                    systemImage: "point.bottomleft.forward.to.point.topright.scurvepath",
                    description: Text("每次真实到访都会在这里留下独立的一条记录，包括未评分的到访。")
                )
                .accessibilityIdentifier("taste-footprints-empty")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(snapshot.footprints.enumerated()), id: \.element.id) { index, item in
                            TasteFootprintRow(
                                item: item,
                                showsTopLine: index > 0,
                                showsBottomLine: index < snapshot.footprints.count - 1,
                                onSelect: {
                                    selectedRestaurant = RestaurantBrowseSelection(id: item.restaurant.id)
                                }
                            )
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
                ContentUnavailableView("餐厅不存在", systemImage: "fork.knife")
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
            timeline
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 11) {
                    header
                    RestaurantBrowsePhoto(photo: item.photo, restaurantID: item.restaurant.id)
                        .frame(maxWidth: .infinity)
                        .frame(height: item.photo == nil ? 112 : 180)
                        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    if let rating = item.visit.rating {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    } else {
                        Label("未评分", systemImage: "star")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let note = item.visit.note, !note.isEmpty {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                    }
                    metadata
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .tasteMapCoreCard(radius: 20)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(0.16))
                }
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
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            Text(item.visit.visitedAt.formatted(date: .abbreviated, time: .shortened))
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
