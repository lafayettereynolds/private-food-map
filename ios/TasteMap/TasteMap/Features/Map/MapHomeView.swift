import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct MapHomeView: View {
    @Query(sort: \Restaurant.createdAt) private var restaurants: [Restaurant]

    @StateObject private var locationPermission = LocationPermissionManager()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedFilter: MapFilter = .visited
    @State private var selectedRestaurantID: UUID?
    @State private var detailDestination: RestaurantDestination?

    private var displayedRestaurants: [Restaurant] {
        switch selectedFilter {
        case .visited:
            restaurants.filter { $0.deletedAt == nil && $0.status == .visited }
        case .wishList:
            restaurants.filter { $0.deletedAt == nil && $0.status == .wantToGo }
        case .forYou:
            []
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Map(position: $cameraPosition, selection: $selectedRestaurantID) {
                    UserAnnotation()
                    ForEach(displayedRestaurants) { restaurant in
                        Marker(
                            restaurant.name,
                            coordinate: CLLocationCoordinate2D(
                                latitude: restaurant.latitude,
                                longitude: restaurant.longitude
                            )
                        )
                        .tag(restaurant.id)
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }
                .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 10) {
                    Picker("地图内容", selection: $selectedFilter) {
                        ForEach(MapFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

                    if locationPermission.isDeniedOrRestricted {
                        Label("定位未开启，仍可浏览地图和搜索餐厅", systemImage: "location.slash")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                if displayedRestaurants.isEmpty {
                    emptyState
                        .padding(.horizontal, 32)
                        .frame(maxHeight: .infinity)
                }

                if selectedFilter == .wishList, !displayedRestaurants.isEmpty {
                    wantToGoList
                }
            }
            .navigationTitle("Taste Map")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                locationPermission.requestWhenInUseAuthorizationIfNeeded()
            }
            .onChange(of: selectedRestaurantID) { _, restaurantID in
                guard let restaurantID else { return }
                detailDestination = RestaurantDestination(id: restaurantID)
            }
            .sheet(item: $detailDestination, onDismiss: {
                selectedRestaurantID = nil
            }) { destination in
                if let restaurant = restaurants.first(where: { $0.id == destination.id && $0.deletedAt == nil }) {
                    RestaurantDetailView(restaurant: restaurant)
                } else {
                    ContentUnavailableView("餐厅不存在", systemImage: "fork.knife")
                }
            }
        }
    }

    private var wantToGoList: some View {
        VStack {
            Spacer()
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(displayedRestaurants) { restaurant in
                        Button {
                            detailDestination = RestaurantDestination(id: restaurant.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                Label("想吃", systemImage: "bookmark.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.blue)
                                Text(restaurant.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                if !restaurant.address.isEmpty {
                                    Text(restaurant.address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .frame(width: 220, alignment: .leading)
                            .padding(14)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("restaurant-card-\(restaurant.id.uuidString)")
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: selectedFilter.systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(selectedFilter.emptyTitle)
                .font(.headline)
            Text(selectedFilter.emptyMessage)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

private enum MapFilter: String, CaseIterable, Identifiable {
    case visited
    case wishList
    case forYou

    var id: Self { self }

    var title: String {
        switch self {
        case .visited: "去过"
        case .wishList: "想吃"
        case .forYou: "适合你"
        }
    }

    var systemImage: String {
        switch self {
        case .visited: "fork.knife.circle"
        case .wishList: "bookmark.circle"
        case .forYou: "sparkles"
        }
    }

    var emptyTitle: String {
        switch self {
        case .visited: "还没有到访记录"
        case .wishList: "还没有想吃的餐厅"
        case .forYou: "个性推荐将在后续版本开放"
        }
    }

    var emptyMessage: String {
        switch self {
        case .visited: "搜索一家真实餐厅，保存第一次到访。"
        case .wishList: "搜索一家真实餐厅，把它加入你的想吃清单。"
        case .forYou: "当前版本不会展示虚构的推荐内容。"
        }
    }
}

private struct RestaurantDestination: Identifiable {
    let id: UUID
}

#Preview("Visited and want-to-go map") {
    let container = try! TasteMapPersistence.makeContainer(inMemory: true)
    let context = container.mainContext
    let visited = Restaurant(
        name: "已经去过的餐厅",
        address: "杭州市上城区",
        latitude: 30.27,
        longitude: 120.20,
        status: .visited,
        syncStatus: .synced
    )
    let wanted = Restaurant(
        name: "很想去尝试的一家名称比较长的餐厅",
        address: "杭州市西湖区文三路",
        latitude: 30.28,
        longitude: 120.13,
        status: .wantToGo,
        syncStatus: .pending
    )
    context.insert(visited)
    context.insert(wanted)
    context.insert(Visit(restaurantId: visited.id, rating: nil, syncStatus: .synced))
    return MapHomeView()
        .modelContainer(container)
}
