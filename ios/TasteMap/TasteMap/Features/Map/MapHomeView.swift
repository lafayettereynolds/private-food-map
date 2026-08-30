import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct MapHomeView: View {
    @Query(sort: \Restaurant.createdAt) private var restaurants: [Restaurant]
    @Query private var visits: [Visit]
    @Query private var photos: [PhotoAsset]
    @Query private var dishes: [Dish]
    @Query private var visitDishes: [VisitDish]
    @Query private var companions: [DiningCompanion]
    @Query private var recommendationSources: [RecommendationSource]

    @Environment(\.photoTransferCoordinator) private var photoCoordinator
    @Environment(\.localAccountScope) private var accountScope
    @StateObject private var locationPermission = LocationPermissionManager()
    @State private var selectedSegment: RestaurantBrowseSegment = .visited
    @State private var browseMode: MapBrowseMode = .map
    @State private var filterState = PersonalRestaurantFilterState(status: .visited)
    @State private var browseQuery = ""
    @State private var isShowingFilters = false
    @State private var locationFilterMessage: String?
    @State private var selectedRestaurantID: UUID?
    @State private var detailDestination: RestaurantBrowseSelection?
    @State private var cameraFitRequestID = UUID()
    @State private var locationRequestID: UUID?
    @State private var mapReloadID = UUID()
    @State private var mapRenderState: RestaurantMapRenderState = .loading

    private let compactControlsHeight: CGFloat = 104

    private var scopedPhotos: [PhotoAsset] {
        photos.filter { accountScope.contains(ownerUserID: $0.ownerUserID) }
    }

    var body: some View {
        let owned = ProfileOwnedContentScope.capture(
            currentUserID: accountScope.ownerUserID,
            restaurants: restaurants,
            visits: visits,
            photos: scopedPhotos,
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
        let filterResult = PersonalRestaurantFilterEngine.resolve(
            snapshot: snapshot,
            state: filterState,
            currentLocation: locationPermission.isDeniedOrRestricted ? nil : locationPermission.currentLocation
        )
        let personalItems = selectedSegment == .forYou ? [] : filterResult.items
        let displayedItems = RestaurantBrowseSearch.filter(personalItems, query: browseQuery)

        NavigationStack {
            ZStack(alignment: .top) {
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
                        },
                        usesSystemSearch: false,
                        contentTopInset: compactControlsHeight
                    )
                }

                controls(
                    resultCount: displayedItems.count,
                    activeFilterCount: filterResult.activeFilterCount
                )
            }
            .background(TasteMapCoreTheme.page)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                locationPermission.requestWhenInUseAuthorizationIfNeeded()
            }
            .onChange(of: selectedSegment) { _, segment in
                switch segment {
                case .visited: filterState.status = .visited
                case .wantToGo: filterState.status = .wantToGo
                case .forYou: break
                }
                requestCameraFit()
            }
            .onChange(of: filterState) { _, _ in requestCameraFit() }
            .onChange(of: browseQuery) { _, _ in requestCameraFit() }
            .onChange(of: browseMode) { _, mode in
                if mode == .map { requestCameraFit() }
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
                if let restaurant = owned.restaurants.first(where: {
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
        VStack(spacing: 6) {
            TasteMapSegmentedControl(
                selection: $selectedSegment,
                items: RestaurantBrowseSegment.allCases.map {
                    .init($0, title: $0.title, systemImage: $0.systemImage)
                },
                accessibilityIdentifier: "map-content-segment"
            )

            HStack(spacing: 7) {
                compactModeControl

                if browseMode == .list {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TasteMapCoreTheme.textSecondary)
                            .accessibilityHidden(true)
                        TextField("搜索餐厅", text: $browseQuery)
                            .font(.subheadline)
                            .textInputAutocapitalization(.never)
                            .submitLabel(.search)
                            .accessibilityIdentifier("restaurant-list-search-field")
                        if !browseQuery.isEmpty {
                            Button {
                                browseQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("清除搜索")
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(TasteMapCoreTheme.surface, in: Capsule())
                    .overlay { Capsule().stroke(TasteMapCoreTheme.border) }
                } else {
                    Spacer(minLength: 0)
                }

                if selectedSegment != .forYou {
                    Button {
                        isShowingFilters = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "line.3.horizontal.decrease")
                            Text(activeFilterCount > 0 ? "筛选后 \(resultCount) 家" : filterState.sort.title)
                                .lineLimit(1)
                            if activeFilterCount > 0 {
                                Text("\(activeFilterCount)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .background(TasteMapCoreTheme.brand, in: Circle())
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TasteMapCoreTheme.brandDeep)
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .background(TasteMapCoreTheme.surface, in: Capsule())
                        .overlay { Capsule().stroke(TasteMapCoreTheme.border) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        activeFilterCount > 0
                            ? "筛选后 \(resultCount) 家，排序\(filterState.sort.title)"
                            : "筛选与排序，当前\(filterState.sort.title)"
                    )
                    .accessibilityIdentifier("personal-filter-button")

                    if activeFilterCount > 0 {
                        Text("筛选后 \(resultCount) 家")
                            .accessibilityIdentifier("personal-filter-result-count")
                            .accessibilityHidden(true)
                        Button(action: clearFilters) {
                            Image(systemName: "xmark")
                                .font(.caption.bold())
                                .frame(width: 32, height: 32)
                                .background(TasteMapCoreTheme.surface, in: Circle())
                                .overlay { Circle().stroke(TasteMapCoreTheme.border) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除筛选")
                        .accessibilityIdentifier("personal-filter-clear")
                    }
                }
            }
        }
        .padding(7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TasteMapCoreTheme.border.opacity(0.82))
        }
        .shadow(color: TasteMapCoreTheme.cardShadow, radius: 10, y: 4)
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map-home-compact-controls")
    }

    private var compactModeControl: some View {
        HStack(spacing: 2) {
            ForEach(MapBrowseMode.allCases) { mode in
                Button {
                    browseMode = mode
                } label: {
                    Image(systemName: mode.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 32)
                        .foregroundStyle(
                            browseMode == mode
                                ? TasteMapCoreTheme.brandDeep
                                : TasteMapCoreTheme.textSecondary
                        )
                        .background(
                            browseMode == mode ? TasteMapCoreTheme.surface : .clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(browseMode == mode ? .isSelected : [])
                .accessibilityIdentifier("map-list-mode-picker-\(mode.title)")
            }
        }
        .padding(2)
        .background(TasteMapCoreTheme.brandSoft, in: RoundedRectangle(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).stroke(TasteMapCoreTheme.border.opacity(0.75)) }
    }

    private func mapContent(
        items: [RestaurantBrowseItem],
        hasUnfilteredItems: Bool,
        activeFilterCount: Int
    ) -> some View {
        let markers = RestaurantMapMarkerBuilder.build(
            items: items,
            photos: scopedPhotos,
            segment: selectedSegment,
            currentLocation: locationPermission.isDeniedOrRestricted
                ? nil
                : locationPermission.currentLocation
        )
        let photosByID = Dictionary(uniqueKeysWithValues: scopedPhotos.map { ($0.id, $0) })

        return ZStack(alignment: .top) {
            ClusteredRestaurantMapView(
                markers: markers,
                photosByID: photosByID,
                photoCoordinator: photoCoordinator,
                selectedRestaurantID: $selectedRestaurantID,
                fitRequestID: cameraFitRequestID,
                locationRequestID: locationRequestID,
                onRenderStateChange: { mapRenderState = $0 }
            )
            .id(mapReloadID)
            .ignoresSafeArea(edges: [.top, .bottom])
            .onChange(of: markers) { _, _ in requestCameraFit() }

            if locationPermission.isDeniedOrRestricted {
                Label("定位未开启，仍可浏览地图和餐厅列表", systemImage: "location.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, compactControlsHeight + 8)
            }

            if case .loading = mapRenderState, !items.isEmpty {
                Label("正在加载地图", systemImage: "map")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, compactControlsHeight + (locationPermission.isDeniedOrRestricted ? 50 : 8))
                    .accessibilityIdentifier("restaurant-map-loading")
            }

            if case let .failed(message) = mapRenderState {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.title2)
                    .foregroundStyle(TasteMapCoreTheme.brand)
                    Text("地图暂时没有加载出来").font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重新加载地图", action: reloadMap)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("restaurant-map-retry")
                }
                .padding(20)
                .background(TasteMapCoreTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(TasteMapCoreTheme.border)
                }
                .padding(.horizontal, 32)
                .padding(.top, compactControlsHeight + 34)
                .accessibilityIdentifier("restaurant-map-error")
            } else if items.isEmpty {
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
                .padding(.top, compactControlsHeight + 34)
            } else if markers.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "mappin.slash.circle")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    Text("餐厅暂无可用坐标").font(.headline)
                    Text("这些记录仍可在列表中查看，补充合法坐标后会显示在地图上。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 32)
                .padding(.top, compactControlsHeight + 34)
                .accessibilityIdentifier("restaurant-map-no-coordinates")
            }

            if selectedSegment == .wantToGo, !items.isEmpty {
                wantToGoCarousel(items: items)
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        locationRequestID = UUID()
                    } label: {
                        Image(systemName: locationPermission.isDeniedOrRestricted ? "location.slash" : "location.fill")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(.regularMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(locationPermission.isDeniedOrRestricted)
                    .accessibilityLabel(locationPermission.isDeniedOrRestricted ? "定位权限未开启" : "显示我的位置")
                    .accessibilityIdentifier("restaurant-map-user-location")
                }
                .padding(.trailing, 14)
                .padding(.bottom, selectedSegment == .wantToGo && !items.isEmpty ? 142 : 16)
            }
        }
    }

    private func requestCameraFit() {
        cameraFitRequestID = UUID()
    }

    private func reloadMap() {
        mapRenderState = .loading
        mapReloadID = UUID()
        requestCameraFit()
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
