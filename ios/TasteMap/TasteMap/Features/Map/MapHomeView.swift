import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct MapHomeView: View {
    @Query(sort: \Restaurant.createdAt) private var restaurants: [Restaurant]
    @Query private var visits: [Visit]
    @Query private var photos: [PhotoAsset]

    @StateObject private var locationPermission = LocationPermissionManager()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedSegment: RestaurantBrowseSegment = .visited
    @State private var browseMode: MapBrowseMode = .map
    @State private var selectedRestaurantID: UUID?
    @State private var detailDestination: RestaurantBrowseSelection?

    var body: some View {
        let snapshot = RestaurantBrowseBuilder.build(
            restaurants: restaurants,
            visits: visits,
            photos: photos
        )
        let displayedItems = snapshot.items(for: selectedSegment)

        NavigationStack {
            VStack(spacing: 0) {
                controls
                if browseMode == .map {
                    mapContent(items: displayedItems)
                } else {
                    RestaurantBrowseList(
                        segment: selectedSegment,
                        items: displayedItems,
                        onSelect: {
                            detailDestination = RestaurantBrowseSelection(id: $0.restaurant.id)
                        }
                    )
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Taste Map")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                locationPermission.requestWhenInUseAuthorizationIfNeeded()
            }
            .onChange(of: selectedRestaurantID) { _, restaurantID in
                guard let restaurantID else { return }
                detailDestination = RestaurantBrowseSelection(id: restaurantID)
            }
            .sheet(item: $detailDestination, onDismiss: {
                selectedRestaurantID = nil
            }) { destination in
                if let restaurant = restaurants.first(where: {
                    $0.id == destination.id && $0.deletedAt == nil
                }) {
                    RestaurantDetailView(restaurant: restaurant)
                } else {
                    ContentUnavailableView("餐厅不存在", systemImage: "fork.knife")
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 9) {
            Picker("地图内容", selection: $selectedSegment) {
                ForEach(RestaurantBrowseSegment.allCases) { segment in
                    Text(segment.title).tag(segment)
                }
            }
            .pickerStyle(.segmented)

            Picker("浏览方式", selection: $browseMode) {
                ForEach(MapBrowseMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("map-list-mode-picker")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func mapContent(items: [RestaurantBrowseItem]) -> some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition, selection: $selectedRestaurantID) {
                UserAnnotation()
                ForEach(items) { item in
                    Marker(
                        item.restaurant.name,
                        coordinate: CLLocationCoordinate2D(
                            latitude: item.restaurant.latitude,
                            longitude: item.restaurant.longitude
                        )
                    )
                    .tag(item.restaurant.id)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea(edges: .bottom)

            if locationPermission.isDeniedOrRestricted {
                Label("定位未开启，仍可浏览地图和餐厅列表", systemImage: "location.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 10)
            }

            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "fork.knife.circle")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    Text(selectedSegment.emptyTitle)
                        .font(.headline)
                    Text(selectedSegment.emptyMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 32)
                .padding(.vertical, 60)
            }

            if selectedSegment == .wantToGo, !items.isEmpty {
                wantToGoCarousel(items: items)
            }
        }
    }

    private func wantToGoCarousel(items: [RestaurantBrowseItem]) -> some View {
        VStack {
            Spacer()
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        Button {
                            detailDestination = RestaurantBrowseSelection(id: item.restaurant.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                Label("想吃", systemImage: "bookmark.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                                Text(item.restaurant.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                let location = [item.restaurant.city, item.restaurant.address]
                                    .filter { !$0.isEmpty }.joined(separator: " · ")
                                if !location.isEmpty {
                                    Text(location)
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
                        .accessibilityIdentifier("restaurant-card-\(item.restaurant.id.uuidString)")
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 12)
    }
}

private enum MapBrowseMode: String, CaseIterable, Identifiable {
    case map
    case list

    var id: Self { self }
    var title: String { self == .map ? "地图" : "列表" }
    var systemImage: String { self == .map ? "map" : "list.bullet" }
}

#Preview("地图 / 列表双模式") {
    let container = try! TasteMapPersistence.makeContainer(inMemory: true)
    let context = container.mainContext
    let visited = Restaurant(
        name: "已经去过的餐厅",
        address: "上城区湖滨路",
        latitude: 30.27,
        longitude: 120.20,
        city: "杭州",
        status: .visited,
        syncStatus: .synced
    )
    let wanted = Restaurant(
        name: "很想去尝试的一家名称比较长的餐厅",
        address: "西湖区文三路",
        latitude: 30.28,
        longitude: 120.13,
        city: "杭州",
        status: .wantToGo,
        syncStatus: .pending
    )
    context.insert(visited)
    context.insert(wanted)
    context.insert(Visit(restaurantId: visited.id, rating: nil, syncStatus: .synced))
    return MapHomeView().modelContainer(container)
}
