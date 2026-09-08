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
    @Query private var profiles: [UserProfile]

    @Environment(\.photoTransferCoordinator) private var photoCoordinator
    @Environment(\.localAccountScope) private var accountScope
    @Environment(\.modelContext) private var modelContext
    @Environment(\.restaurantRouletteSession) private var rouletteSession
    @StateObject private var locationPermission = LocationPermissionManager()
    @State private var scopeQueries = PersonalRestaurantScopeQueries()
    @State private var browseMode: MapBrowseMode = .map
    private var selectedSegment: RestaurantBrowseSegment { scopeQueries.scope }
    private var filterState: PersonalRestaurantFilterState {
        get { scopeQueries.current.filters }
        nonmutating set { scopeQueries.current.filters = newValue; requestCameraFit() }
    }
    private var browseQuery: String {
        get { scopeQueries.current.search }
        nonmutating set { scopeQueries.current.search = newValue; requestCameraFit() }
    }
    @State private var filterFocus: PersonalRestaurantFilterFocus?
    @State private var locationFilterMessage: String?
    @State private var selectedRestaurantID: UUID?
    @State private var detailDestination: RestaurantBrowseSelection?
    @State private var visitEditorDestination: RestaurantBrowseSelection?
    @State private var quickActionMessage: String?
    @State private var cameraFitRequestID = UUID()
    @State private var locationRequestID: UUID?
    @State private var mapReloadID = UUID()
    @State private var mapRenderState: RestaurantMapRenderState = .loading
    @State private var showsCompletedTasteDataProgress = false

    private let compactControlsHeight: CGFloat = 154

    private var scopedPhotos: [PhotoAsset] {
        photos.filter { accountScope.contains(ownerUserID: $0.ownerUserID) }
    }

    private var activeProfile: UserProfile? {
        guard let ownerUserID = accountScope.ownerUserID else { return nil }
        return profiles.first {
            $0.tasteMapUserID == ownerUserID && $0.deletedAt == nil
        }
    }

    private var avatarPhoto: PhotoAsset? {
        guard let reference = activeProfile?.avatarPhotoID?.lowercased() else { return nil }
        return scopedPhotos.first {
            ($0.remoteID?.lowercased() == reference
                || $0.id.uuidString.lowercased() == reference)
                && $0.deletedAt == nil
        }
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
        let tasteDataProgress = TasteDataProgressPolicy.resolve(
            activeRestaurantIDs: Set(owned.restaurants.filter { $0.deletedAt == nil }.map(\.id)),
            visits: owned.visits.map {
                TasteDataProgressVisit(
                    restaurantID: $0.restaurantId,
                    rating: $0.rating,
                    isDeleted: $0.deletedAt != nil
                )
            }
        )
        let visibleTasteDataProgress = browseMode == .map
            && (!tasteDataProgress.isComplete || showsCompletedTasteDataProgress)

        NavigationStack {
            ZStack(alignment: .top) {
                if browseMode == .map {
                    mapContent(
                        items: displayedItems,
                        hasUnfilteredItems: !snapshot.items(for: selectedSegment).isEmpty,
                        activeFilterCount: filterResult.activeFilterCount,
                        tasteDataProgress: visibleTasteDataProgress ? tasteDataProgress : nil
                    )
                } else {
                    RestaurantBrowseList(
                        segment: selectedSegment,
                        items: displayedItems,
                        query: Binding(get: { browseQuery }, set: { browseQuery = $0 }),
                        isFiltered: filterResult.activeFilterCount > 0,
                        onClearFilters: clearFilters,
                        onSelect: {
                            detailDestination = RestaurantBrowseSelection(id: $0.restaurant.id)
                        },
                        onRecordVisit: {
                            visitEditorDestination = RestaurantBrowseSelection(id: $0.restaurant.id)
                        },
                        onToggleWantToGo: {
                            toggleWantToGo($0.restaurant)
                        },
                        onOpenRoulette: {
                            _ = rouletteSession?.toggle($0.restaurant.id)
                        },
                        usesSystemSearch: false,
                        showsContextHeader: true,
                        contentTopInset: compactControlsHeight,
                        contentBottomInset: 84
                    )
                }

                controls(
                    resultCount: displayedItems.count,
                    activeFilterCount: filterResult.activeFilterCount,
                    options: snapshot.filterOptions(for: selectedSegment),
                    scopeCounts: [
                        .visited: snapshot.visited.count,
                        .wantToGo: snapshot.wantToGo.count,
                        .forYou: 0,
                    ]
                )
            }
            .background(TasteMapCoreTheme.page)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                locationPermission.requestWhenInUseAuthorizationIfNeeded()
            }
            .task(id: "\(accountScope.ownerUserID ?? "local")|\(tasteDataProgress.ratedRestaurantCount)|\(browseMode.rawValue)") {
                await updateCompletedTasteDataProgress(
                    tasteDataProgress,
                    ownerUserID: accountScope.ownerUserID
                )
            }
            .onChange(of: accountScope.ownerUserID) { _, _ in
                scopeQueries = PersonalRestaurantScopeQueries()
            }
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
                    RestaurantDetailView(restaurant: restaurant, entrySource: .map)
                } else {
                    TasteMapEmptyState(
                        title: "餐厅不存在",
                        message: "这家餐厅可能已经被删除或尚未同步完成。",
                        systemImage: "fork.knife",
                        presentation: .embedded
                    )
                }
            }
            .sheet(item: $visitEditorDestination) { destination in
                if let restaurant = owned.restaurants.first(where: {
                    $0.id == destination.id && $0.deletedAt == nil
                }) {
                    VisitEditorView(restaurant: restaurant)
                } else {
                    TasteMapEmptyState(
                        title: "餐厅不存在",
                        message: "这家餐厅可能已经被删除或尚未同步完成。",
                        systemImage: "fork.knife",
                        presentation: .embedded
                    )
                }
            }
            .sheet(item: $filterFocus) { focus in
                PersonalRestaurantFilterSheet(
                    state: filterState,
                    options: snapshot.filterOptions(for: selectedSegment),
                    locationDenied: locationPermission.isDeniedOrRestricted,
                    hasCurrentLocation: locationPermission.currentLocation != nil,
                    focus: focus,
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
            .alert("餐厅快捷操作", isPresented: Binding(
                get: { quickActionMessage != nil },
                set: { if !$0 { quickActionMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { quickActionMessage = nil }
            } message: {
                Text(quickActionMessage ?? "")
            }
        }
    }

    private func controls(
        resultCount: Int,
        activeFilterCount: Int,
        options: PersonalRestaurantFilterOptions,
        scopeCounts: [RestaurantBrowseSegment: Int]
    ) -> some View {
        VStack(spacing: 5) {
            MapBrowseTitleSwitch(browseMode: $browseMode)
            .frame(maxWidth: .infinity, alignment: .center)

            TasteMapPrimaryTabBar(
                selection: Binding(get: { selectedSegment }, set: {
                    scopeQueries.scope = $0
                    selectedRestaurantID = nil
                }),
                items: [
                    .init(.visited, title: "去过", count: scopeCounts[.visited], accessibilityIdentifier: "map-scope-visited"),
                    .init(.wantToGo, title: "想吃", count: scopeCounts[.wantToGo], accessibilityIdentifier: "map-scope-wantToGo"),
                    .init(.forYou, title: "推荐", count: scopeCounts[.forYou], accessibilityIdentifier: "map-scope-forYou"),
                ],
                accessibilityIdentifier: "map-content-segment"
            )

            TasteMapFilterBar(horizontalPadding: 0, accessibilityIdentifier: "map-filter-chip-strip") {
                HStack(spacing: 7) {
                    TasteMapFilterChip(
                        title: "筛选",
                        semantic: .allFilters,
                        isActive: activeFilterCount > 0,
                        count: activeFilterCount,
                        accessibilityIdentifier: "personal-filter-button"
                    ) { filterFocus = .all }

                    if browseMode == .list {
                        listSearchChip
                    }

                    filterSummaryChip(
                        focus: .city,
                        title: filterState.city ?? "城市",
                        semantic: .city,
                        isActive: filterState.city != nil,
                        identifier: "map-filter-chip-city"
                    )

                    filterSummaryChip(
                        focus: .rating,
                        title: filterState.ratingBands.isEmpty
                            ? "评分"
                            : filterState.ratingBands.sorted { $0.rawValue > $1.rawValue }
                                .map(\.title).joined(separator: "、"),
                        semantic: .rating,
                        isActive: !filterState.ratingBands.isEmpty,
                        identifier: "map-filter-chip-rating"
                    )

                    if filterState.appliesVisitScopedFilters {
                        filterSummaryChip(
                            focus: .price,
                            title: filterState.priceRange?.title ?? "消费",
                            semantic: .price,
                            isActive: filterState.priceRange != nil,
                            identifier: "map-filter-chip-price"
                        )
                        filterSummaryChip(
                            focus: .visitCount,
                            title: filterState.visitCount.map { "到访 \($0.title)" } ?? "到访次数",
                            semantic: .visitCount,
                            isActive: filterState.visitCount != nil,
                            identifier: "map-filter-chip-visits"
                        )
                        if !options.companions.isEmpty {
                            filterSummaryChip(
                                focus: .companion,
                                title: selectedOptionTitle(id: filterState.companionID, in: options.companions) ?? "饭搭子",
                                semantic: .companion,
                                isActive: filterState.companionID != nil,
                                identifier: "map-filter-chip-companion"
                            )
                        }
                        if !options.cuisines.isEmpty {
                            filterSummaryChip(
                                focus: .cuisine,
                                title: filterState.cuisine ?? "菜系",
                                semantic: .cuisine,
                                isActive: filterState.cuisine != nil,
                                identifier: "map-filter-chip-cuisine"
                            )
                        }
                        if !options.sources.isEmpty {
                            filterSummaryChip(
                                focus: .recommendationSource,
                                title: selectedOptionTitle(id: filterState.sourceID, in: options.sources) ?? "推荐来源",
                                semantic: .recommendationSource,
                                isActive: filterState.sourceID != nil,
                                identifier: "map-filter-chip-source"
                            )
                        }
                    }

                    filterSummaryChip(
                        focus: .sort,
                        title: filterState.sort.title,
                        semantic: .sort,
                        isActive: filterState.sort != .comprehensive,
                        identifier: "map-filter-chip-sort"
                    )

                    if activeFilterCount > 0 {
                        TasteMapFilterChip(
                            title: "清除",
                            semantic: .clear,
                            isActive: false,
                            accessibilityIdentifier: "personal-filter-clear",
                            action: clearFilters
                        )

                        Text("筛选后 \(resultCount) 家")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(TasteMapCoreTheme.textSecondary)
                            .accessibilityIdentifier("personal-filter-result-count")
                    }
                }
                .padding(.horizontal, 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 18)
        .padding(.bottom, 8)
        .background(TasteMapCoreTheme.page.opacity(0.97))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map-home-compact-controls")
    }

    private var listSearchChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TasteMapCoreTheme.textSecondary)
                .accessibilityHidden(true)
            TextField("搜索餐厅", text: Binding(get: { browseQuery }, set: { browseQuery = $0 }))
                .font(.caption)
                .frame(width: 112)
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
        .padding(.horizontal, TasteMapDesignTokens.Control.filterChipHorizontalPadding)
        .frame(height: TasteMapDesignTokens.Control.chipVisibleHeight)
        .background(TasteMapCoreTheme.surface, in: Capsule())
        .overlay { Capsule().stroke(TasteMapCoreTheme.border) }
    }

    private func filterSummaryChip(
        focus: PersonalRestaurantFilterFocus,
        title: String,
        semantic: TasteMapFilterSemantic,
        isActive: Bool,
        identifier: String
    ) -> some View {
        TasteMapFilterChip(
            title: title,
            semantic: semantic,
            isActive: isActive,
            accessibilityIdentifier: identifier
        ) {
            filterFocus = focus
        }
    }

    private func selectedOptionTitle(id: String?, in options: [PersonalFilterOption]) -> String? {
        guard let id else { return nil }
        return options.first(where: { $0.id == id })?.title
    }

    private func mapContent(
        items: [RestaurantBrowseItem],
        hasUnfilteredItems: Bool,
        activeFilterCount: Int,
        tasteDataProgress: TasteDataProgressSnapshot?
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
        let topNoticeOffset: CGFloat = (tasteDataProgress == nil ? 0 : 30)
            + (locationPermission.isDeniedOrRestricted ? 42 : 0)

        return ZStack(alignment: .top) {
            RestaurantMapView(
                markers: markers,
                photosByID: photosByID,
                photoCoordinator: photoCoordinator,
                photoAPI: nil,
                userAvatarPreset: activeProfile?.avatarPreset ?? .polarBear,
                userAvatarPhoto: avatarPhoto,
                showsUserLocation: true,
                selectedRestaurantID: $selectedRestaurantID,
                fitRequestID: cameraFitRequestID,
                locationRequestID: locationRequestID,
                onRenderStateChange: { mapRenderState = $0 },
                onViewportChange: { _ in }
            )
            .id(mapReloadID)
            .ignoresSafeArea(edges: [.top, .bottom])
            .onChange(of: markers) { _, _ in requestCameraFit() }

            VStack(spacing: TasteMapDesignTokens.Spacing.small) {
                if let tasteDataProgress {
                    TasteDataProgressNotice(progress: tasteDataProgress)
                }

                if locationPermission.isDeniedOrRestricted {
                    Label("定位未开启，仍可浏览地图和餐厅列表", systemImage: "location.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                }

                if case .loading = mapRenderState, !items.isEmpty {
                    Label("正在加载地图", systemImage: "map")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .accessibilityIdentifier("restaurant-map-loading")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, TasteMapDesignTokens.Spacing.regular)
            .padding(.top, compactControlsHeight + TasteMapDesignTokens.Spacing.small)

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
                .padding(.top, compactControlsHeight + 34 + topNoticeOffset)
                .accessibilityIdentifier("restaurant-map-error")
            } else if items.isEmpty {
                VStack(spacing: 10) {
                    if activeFilterCount > 0 && hasUnfilteredItems {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                    } else {
                        FoodDiningVisualIcon(
                            kind: .genericDining,
                            usage: .decorative,
                            size: 44
                        )
                    }
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
                .padding(.top, compactControlsHeight + 34 + topNoticeOffset)
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
                .padding(.top, compactControlsHeight + 34 + topNoticeOffset)
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
                .padding(.bottom, selectedSegment == .wantToGo && !items.isEmpty ? 194 : 70)
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

    private func updateCompletedTasteDataProgress(
        _ progress: TasteDataProgressSnapshot,
        ownerUserID: String?
    ) async {
        let storageKey = TasteDataProgressPolicy.completionStorageKey(ownerUserID: ownerUserID)
        guard progress.isComplete else {
            UserDefaults.standard.removeObject(forKey: storageKey)
            showsCompletedTasteDataProgress = false
            return
        }
        guard browseMode == .map else { return }
        guard !UserDefaults.standard.bool(forKey: storageKey) else {
            showsCompletedTasteDataProgress = false
            return
        }

        showsCompletedTasteDataProgress = true
        do {
            try await Task.sleep(for: .seconds(6))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        UserDefaults.standard.set(true, forKey: storageKey)
        withAnimation(.easeOut(duration: 0.2)) {
            showsCompletedTasteDataProgress = false
        }
    }

    private func clearFilters() {
        filterState.resetKeepingStatus()
    }

    private func toggleWantToGo(_ restaurant: Restaurant) {
        if restaurant.status == .visited {
            quickActionMessage = "「\(restaurant.name)」已经在去过清单里，可以继续记录到访。"
            return
        }
        do {
            try LocalTasteMapStore(context: modelContext).delete(
                restaurant,
                actorUserID: accountScope.ownerUserID
            )
            quickActionMessage = "「\(restaurant.name)」已移出想吃。"
        } catch {
            quickActionMessage = "暂时无法更新想吃状态，请稍后重试。"
        }
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
        let requestedScope = selectedSegment
        Task { @MainActor in
            do {
                _ = try await locationPermission.requestCurrentLocation()
                guard selectedSegment == requestedScope else { return }
                filterState = proposedState
            } catch {
                guard selectedSegment == requestedScope else { return }
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

nonisolated struct TasteDataProgressVisit: Equatable, Sendable {
    let restaurantID: UUID
    let rating: Double?
    let isDeleted: Bool
}

nonisolated struct TasteDataProgressSnapshot: Equatable, Sendable {
    let ratedRestaurantCount: Int
    let displayCount: Int
    let target: Int
    let remaining: Int
    let message: String
    let fraction: Double

    var isComplete: Bool { ratedRestaurantCount >= 20 }
}

nonisolated enum TasteDataProgressPolicy {
    static func resolve(
        activeRestaurantIDs: Set<UUID>,
        visits: [TasteDataProgressVisit]
    ) -> TasteDataProgressSnapshot {
        let ratedRestaurantIDs = Set(visits.compactMap { visit -> UUID? in
            guard !visit.isDeleted,
                  activeRestaurantIDs.contains(visit.restaurantID),
                  isValidRating(visit.rating) else { return nil }
            return visit.restaurantID
        })
        return resolve(ratedRestaurantCount: ratedRestaurantIDs.count)
    }

    static func resolve(ratedRestaurantCount value: Int) -> TasteDataProgressSnapshot {
        let ratedRestaurantCount = max(0, value)
        let displayCount = min(ratedRestaurantCount, 20)
        let target: Int
        switch ratedRestaurantCount {
        case ...5: target = 5
        case ...10: target = 10
        case ...15: target = 15
        default: target = 20
        }
        let remaining = max(0, target - displayCount)
        let message: String
        if remaining > 0 {
            switch ratedRestaurantCount {
            case ...5: message = "再评分 \(remaining) 家，开始形成你的口味判断"
            case ...10: message = "再评分 \(remaining) 家，推荐和分析会更准确"
            case ...15: message = "再评分 \(remaining) 家，口味分析会更完整"
            default: message = "再评分 \(remaining) 家，口味判断会更稳定"
            }
        } else {
            switch target {
            case 5: message = "开始形成你的口味判断"
            case 10: message = "推荐和分析正在变得更准确"
            case 15: message = "口味分析正在变得更完整"
            default: message = "口味数据已较稳定"
            }
        }
        return TasteDataProgressSnapshot(
            ratedRestaurantCount: ratedRestaurantCount,
            displayCount: displayCount,
            target: target,
            remaining: remaining,
            message: message,
            fraction: Double(displayCount) / Double(target)
        )
    }

    static func completionStorageKey(ownerUserID: String?) -> String {
        let normalized = ownerUserID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let owner = normalized.flatMap { $0.isEmpty ? nil : $0 } ?? "local"
        return "taste-map.taste-data-progress.complete.\(owner)"
    }

    private static func isValidRating(_ value: Double?) -> Bool {
        guard let value, value.isFinite, (0.5...5).contains(value) else { return false }
        return (value * 2).rounded() == value * 2
    }
}

private struct TasteDataProgressNotice: View {
    let progress: TasteDataProgressSnapshot

    var body: some View {
        Text("（\(progress.displayCount) / \(progress.target) · \(progress.message)）")
            .font(.caption2.monospacedDigit().weight(.bold))
            .foregroundStyle(TasteMapCoreTheme.brand)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .shadow(color: TasteMapCoreTheme.surface.opacity(0.98), radius: 3)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("口味数据进度，\(progress.displayCount) / \(progress.target)，\(progress.message)")
            .accessibilityIdentifier("taste-data-progress-notice")
    }
}

/// Testable semantic contract for the chips shown together in the Map header.
/// Every data dimension in this group has an icon; city intentionally uses a
/// building symbol because it is a city filter, not current GPS location.
enum MapHomeControlLayer: String, CaseIterable, Sendable {
    case title
    case restaurantScope
    case filters
}

enum MapBrowseMode: String, CaseIterable, Identifiable {
    case map
    case list

    var id: Self { self }
    var title: String { self == .map ? "地图" : "列表" }
    var systemImage: String { self == .map ? "map" : "list.bullet" }

    var pageTitle: String { self == .map ? "我的地图" : "我的列表" }
    var switchAccessibilityLabel: String {
        self == .map ? "切换到我的列表" : "切换到我的地图"
    }
    var switchAccessibilityIdentifier: String {
        self == .map ? "map-header-view-list" : "map-header-view-map"
    }
}

/// The title and current-view icon form one fixed-width visual group. The
/// parent centres this complete group instead of independently centring the
/// text and leaving a destination icon floating on the trailing edge.
struct MapBrowseTitleSwitch: View {
    @Binding var browseMode: MapBrowseMode

    var body: some View {
        HStack(spacing: 4) {
            Text(browseMode.pageTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(TasteMapCoreTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("map-home-title")

            Button {
                browseMode = browseMode == .map ? .list : .map
            } label: {
                Image(systemName: browseMode.systemImage)
                    .font(.subheadline.weight(.bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(TasteMapCoreTheme.brandDeep)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MapBrowseTitleIconButtonStyle())
            .accessibilityLabel(browseMode.switchAccessibilityLabel)
            .accessibilityHint("切换地图和列表视图")
            .accessibilityValue("当前显示\(browseMode.pageTitle)")
            .accessibilityIdentifier(browseMode.switchAccessibilityIdentifier)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map-title-view-switch")
        .sensoryFeedback(.selection, trigger: browseMode)
    }
}

private struct MapBrowseTitleIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle()
                    .fill(
                        configuration.isPressed
                            ? TasteMapCoreTheme.brand.opacity(0.16)
                            : TasteMapCoreTheme.brandSoft.opacity(0.62)
                    )
                    .frame(width: 30, height: 30)
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
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
