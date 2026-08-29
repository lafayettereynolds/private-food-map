import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct MapHomeView: View {
    @Query(sort: \Restaurant.createdAt) private var restaurants: [Restaurant]
    @Query private var visits: [Visit]
    @Query private var photos: [PhotoAsset]
    @Query private var companions: [DiningCompanion]
    @Query private var recommendationSources: [RecommendationSource]

    @StateObject private var locationPermission = LocationPermissionManager()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedSegment: RestaurantBrowseSegment = .visited
    @State private var browseMode: MapBrowseMode = .map
    @State private var filterState = PersonalRestaurantFilterState(status: .visited)
    @State private var browseQuery = ""
    @State private var isShowingFilters = false
    @State private var locationFilterMessage: String?
    @State private var selectedRestaurantID: UUID?
    @State private var detailDestination: RestaurantBrowseSelection?

    var body: some View {
        let snapshot = RestaurantBrowseBuilder.build(
            restaurants: restaurants,
            visits: visits,
            photos: photos,
            companions: companions,
            recommendationSources: recommendationSources
        )
        let filterResult = PersonalRestaurantFilterEngine.resolve(
            snapshot: snapshot,
            state: filterState,
            currentLocation: locationPermission.isDeniedOrRestricted ? nil : locationPermission.currentLocation
        )
        let personalItems = selectedSegment == .forYou ? [] : filterResult.items
        let displayedItems = RestaurantBrowseSearch.filter(personalItems, query: browseQuery)

        NavigationStack {
            VStack(spacing: 0) {
                controls(
                    resultCount: displayedItems.count,
                    activeFilterCount: filterResult.activeFilterCount
                )
                if browseMode == .map {
                    mapContent(
                        items: displayedItems,
                        hasUnfilteredItems: !snapshot.items(for: selectedSegment).isEmpty,
                        activeFilterCount: filterResult.activeFilterCount
                    )
                } else {
                    RestaurantBrowseList(
                        segment: selectedSegment,
                        items: displayedItems,
                        query: $browseQuery,
                        isFiltered: filterResult.activeFilterCount > 0,
                        onClearFilters: clearFilters,
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
            .onChange(of: selectedSegment) { _, segment in
                switch segment {
                case .visited: filterState.status = .visited
                case .wantToGo: filterState.status = .wantToGo
                case .forYou: break
                }
            }
            .onChange(of: locationPermission.isDeniedOrRestricted) { _, denied in
                if denied, filterState.distance != nil {
                    filterState.distance = nil
                    locationFilterMessage = "定位权限未开启，已保留其他筛选并移除距离条件。"
                }
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
            .sheet(isPresented: $isShowingFilters) {
                PersonalRestaurantFilterSheet(
                    state: filterState,
                    options: snapshot.filterOptions,
                    locationDenied: locationPermission.isDeniedOrRestricted,
                    hasCurrentLocation: locationPermission.currentLocation != nil,
                    onApply: applyFilters
                )
            }
            .alert("距离筛选", isPresented: Binding(
                get: { locationFilterMessage != nil },
                set: { if !$0 { locationFilterMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { locationFilterMessage = nil }
            } message: {
                Text(locationFilterMessage ?? "")
            }
        }
    }

    private func controls(resultCount: Int, activeFilterCount: Int) -> some View {
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

            if selectedSegment != .forYou {
                HStack(spacing: 10) {
                    Button {
                        isShowingFilters = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            Text("筛选")
                            if activeFilterCount > 0 {
                                Text("\(activeFilterCount)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 20, minHeight: 20)
                                    .background(Color.accentColor, in: Circle())
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("personal-filter-button")

                    Text(filterState.sort.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if activeFilterCount > 0 {
                        Text("筛选后 \(resultCount) 家")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("personal-filter-result-count")
                        Button("清除", action: clearFilters)
                            .font(.caption.weight(.semibold))
                            .accessibilityIdentifier("personal-filter-clear")
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func mapContent(
        items: [RestaurantBrowseItem],
        hasUnfilteredItems: Bool,
        activeFilterCount: Int
    ) -> some View {
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
                VStack(spacing: 10) {
                    Image(systemName: activeFilterCount > 0 ? "line.3.horizontal.decrease.circle" : "fork.knife.circle")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    Text(activeFilterCount > 0 && hasUnfilteredItems ? "当前无符合条件的餐厅" : selectedSegment.emptyTitle)
                        .font(.headline)
                    Text(activeFilterCount > 0 && hasUnfilteredItems ? "可以清除筛选，重新查看你的餐厅。" : selectedSegment.emptyMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if activeFilterCount > 0 && hasUnfilteredItems {
                        Button("清除全部筛选", action: clearFilters)
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("personal-filter-zero-clear")
                    }
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

    private func clearFilters() {
        filterState.resetKeepingStatus()
    }

    private func applyFilters(_ proposedState: PersonalRestaurantFilterState) {
        guard proposedState.distance != nil else {
            filterState = proposedState
            return
        }
        guard !locationPermission.isDeniedOrRestricted else {
            var adjusted = proposedState
            adjusted.distance = nil
            filterState = adjusted
            locationFilterMessage = "定位权限未开启，距离筛选不可用；其他条件已经应用。"
            return
        }
        if locationPermission.currentLocation != nil {
            filterState = proposedState
            return
        }
        Task { @MainActor in
            do {
                _ = try await locationPermission.requestCurrentLocation()
                filterState = proposedState
            } catch {
                var adjusted = proposedState
                adjusted.distance = nil
                filterState = adjusted
                locationFilterMessage = "暂时无法取得当前位置，已保留其他筛选并移除距离条件。"
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
