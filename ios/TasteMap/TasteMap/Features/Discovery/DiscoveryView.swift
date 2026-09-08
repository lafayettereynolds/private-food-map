import SwiftData
import SwiftUI
import UIKit
import CoreLocation

struct DiscoveryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NativeAuthServices.self) private var authServices
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Environment(PremiumEntitlementService.self) private var premiumEntitlementService
    @Environment(\.localAccountScope) private var accountScope
    @Query private var restaurants: [Restaurant]
    @Query private var profiles: [UserProfile]

    let showsModePicker: Bool
    let showsNavigationTitle: Bool

    @State private var mode: DiscoveryModeV1
    @State private var trendWindowDays = 7
    @State private var authenticatedUser: AuthenticatedUserV1?
    @State private var cards: [DiscoveryCardV1] = []
    @State private var excludedRecommendationIDs: Set<String>?
    @State private var recommendationIntentFeedback = RestaurantRecommendationIntentFeedback()
    @State private var nextCursor: String?
    @State private var loading = false
    @State private var loadingMore = false
    @State private var message: String?
    @State private var evidenceAvailability: TasteMapDiscoveryEvidenceAvailabilityDTO?
    @State private var addingEvidence = false
    @State private var pendingEvidenceCandidate: RestaurantCandidate?
    @State private var evidenceVisitCandidate: RestaurantCandidate?
    @State private var refreshIssue: TasteMapHybridBridgeErrorDTO?
    @State private var cacheDate: Date?
    @State private var showingCache = false
    @State private var selectedCard: DiscoveryCardV1?
    @State private var selectedUser: DiscoveryPublicUserProjectionV1?
    @State private var selectedVisitCard: DiscoveryCardV1?
    @State private var selectedListCard: DiscoveryCardV1?
    @State private var selectedRouletteRestaurantID: UUID?
    @State private var selectedCity = ""
    @State private var didInitializeCity = false
    @State private var browseFilters = DiscoveryBrowseFilters()
    @State private var distanceAnchor: DiscoveryBrowseCoordinate?
    @State private var distanceAnchorDescription: String?
    @StateObject private var locationManager = LocationPermissionManager()

    init(
        initialMode: DiscoveryModeV1 = .forYou,
        showsModePicker: Bool = true,
        showsNavigationTitle: Bool = true
    ) {
        self.showsModePicker = showsModePicker
        self.showsNavigationTitle = showsNavigationTitle
        _mode = State(initialValue: initialMode)
    }

    private var ownedRestaurants: [Restaurant] {
        restaurants.filter { accountScope.contains(ownerUserID: $0.ownerUserID) }
    }

    private var defaultCity: String {
        if let userID = authenticatedUser?.id,
           let profileCity = profiles.first(where: { $0.tasteMapUserID == userID && $0.deletedAt == nil })?.city,
           !profileCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return profileCity }
        return ownedRestaurants.filter { $0.deletedAt == nil && !$0.city.isEmpty }
            .sorted { $0.updatedAt > $1.updatedAt }.first?.city ?? ""
    }

    private var city: String { didInitializeCity ? selectedCity : defaultCity }

    private func refreshRecommendationPreferences() {
        guard let owner = accountScope.authenticatedUserID else {
            excludedRecommendationIDs = nil; recommendationIntentFeedback = .init(); return
        }
        do {
            let snapshot = try RestaurantRecommendationPreferences.snapshot(ownerID: owner, context: modelContext)
            excludedRecommendationIDs = Set(snapshot.excludedIDs)
            recommendationIntentFeedback = snapshot.intentFeedback
        } catch {
            excludedRecommendationIDs = nil; recommendationIntentFeedback = .init()
            message = "推荐偏好暂时无法读取，请重试。"
        }
    }

    private var availableCities: [String] {
        Set(
            ownedRestaurants.filter { $0.deletedAt == nil }.map(\.city) +
                profiles.filter { $0.deletedAt == nil }.compactMap(\.city) +
                cards.map(\.restaurant.city)
        )
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var browseResolution: DiscoveryBrowseResolution {
        let resolution = DiscoveryBrowseResolver.resolve(
            cards: mode == .forYou ? cards.filter { card in
                excludedRecommendationIDs != nil && !excludedRecommendationIDs!.contains(card.restaurant.globalKey.lowercased())
                    && RestaurantRecommendationIntentPolicy.permits(name: card.restaurant.name, tags: card.restaurant.tags,
                                                                    feedback: recommendationIntentFeedback)
            } : cards,
            filters: mode == .forYou ? browseFilters : DiscoveryBrowseFilters(),
            anchor: distanceAnchor
        )
        guard mode == .forYou, browseFilters.sort == .recommended else { return resolution }
        return DiscoveryBrowseResolution(cards: RestaurantRecommendationIntentPolicy.stablePriority(
            resolution.cards, feedback: recommendationIntentFeedback,
            metadata: { ($0.restaurant.name, $0.restaurant.tags) }), emptyReason: resolution.emptyReason)
    }

    var body: some View {
        NavigationStack {
            DiscoveryContentView(
                mode: $mode, trendWindowDays: $trendWindowDays,
                cards: browseResolution.cards, unfilteredCardCount: cards.count,
                loading: loading, loadingMore: loadingMore, message: message,
                refreshIssue: refreshIssue,
                cacheDate: cacheDate, showingCache: showingCache,
                isSignedIn: authenticatedUser != nil,
                similarTasteAccess: premiumEntitlementService.access(for: .similarTaste),
                city: city, availableCities: availableCities,
                filters: $browseFilters,
                filterEmptyReason: mode == .forYou ? browseResolution.emptyReason : nil,
                distanceAnchorDescription: mode == .forYou ? distanceAnchorDescription : nil,
                canLoadMore: nextCursor != nil,
                onSelectCity: selectCity,
                onResetFilters: resetFilters,
                onRetry: { Task { await load(reset: true, preferCache: false) } },
                onOpenRestaurant: { selectedCard = $0 },
                onWantToGo: addToWantToGo,
                onRecordVisit: { selectedVisitCard = $0 },
                onAddToList: { selectedListCard = $0 },
                onAddToRoulette: addToRoulette,
                onOpenUser: { selectedUser = $0 },
                onLoadMore: { Task { await loadMore() } },
                photoAPI: authServices.photoAPI,
                showsModePicker: showsModePicker,
                evidenceAvailability: evidenceAvailability,
                onAddEvidence: { addingEvidence = true }
            )
            .navigationTitle(showsNavigationTitle ? "发现" : "")
            .toolbar(showsNavigationTitle ? .visible : .hidden, for: .navigationBar)
            .background(TasteMapCoreTheme.page)
            .refreshable { await load(reset: true, preferCache: false) }
            .task { await restoreAndLoad() }
            .task(id: accountScope.authenticatedUserID) { refreshRecommendationPreferences() }
            .onReceive(NotificationCenter.default.publisher(for: RestaurantRecommendationPreferences.didChange)) { _ in refreshRecommendationPreferences() }
            .onChange(of: mode) { _, _ in Task { await load(reset: true, preferCache: true) } }
            .onChange(of: premiumEntitlementService.membershipStatus) { _, _ in
                guard mode == .similarTaste else { return }
                Task { await load(reset: true, preferCache: true) }
            }
            .onChange(of: trendWindowDays) { _, _ in
                guard mode == .trending else { return }
                Task { await load(reset: true, preferCache: true) }
            }
            .onChange(of: browseFilters) { _, _ in
                Task { await establishDistanceAnchorIfNeeded() }
            }
            .sheet(item: $selectedCard) { card in
                DiscoveryRestaurantDestination(
                    card: card, restaurants: ownedRestaurants,
                    onWantToGo: { addToWantToGo(card) },
                    onViewerStateChange: { updateViewerState(for: card.restaurant.globalKey, state: $0) },
                    photoAPI: authServices.photoAPI
                )
            }
            .sheet(item: $selectedVisitCard) { card in
                VisitEditorView(
                    candidate: card.restaurant.restaurantCandidate,
                    onVisitSaved: { _ in
                        updateViewerState(for: card.restaurant.globalKey, state: .visited)
                        Task { await syncCoordinator.synchronizeNow() }
                    }
                )
            }
            .sheet(isPresented: $addingEvidence, onDismiss: {
                evidenceVisitCandidate = pendingEvidenceCandidate
                pendingEvidenceCandidate = nil
            }) {
                AddRestaurantView(dependencies: .live(linkResolver: authServices.externalRestaurantLinkAPI)) { candidate, action in
                    switch action {
                    case .wantToGo:
                        _ = try LocalTasteMapStore(context: modelContext).addToWantToGo(
                            candidate: candidate, among: ownedRestaurants, actorUserID: accountScope.ownerUserID)
                    case .recordVisit: pendingEvidenceCandidate = candidate
                    }
                }
            }
            .sheet(item: $evidenceVisitCandidate) { candidate in
                VisitEditorView(candidate: candidate, onVisitSaved: { _ in
                    Task { await syncCoordinator.synchronizeNow(); await load(reset: true, preferCache: false) }
                })
            }
            .sheet(item: $selectedListCard) { card in
                if let userID = authenticatedUser?.id {
                    AddPlaceToListsSheet(place: card.restaurant, currentUserID: userID)
                }
            }
            .sheet(isPresented: Binding(
                get: { selectedRouletteRestaurantID != nil },
                set: { if !$0 { selectedRouletteRestaurantID = nil } }
            )) {
                NavigationStack {
                    RestaurantRouletteScreen(preferredCity: city, initialRestaurantID: selectedRouletteRestaurantID)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("完成") { selectedRouletteRestaurantID = nil }
                            }
                        }
                }
            }
            .sheet(item: $selectedUser) { user in
                if let currentUserID = authenticatedUser?.id {
                    SocialPublicProfileView(
                        initial: user.socialResult, currentUserID: currentUserID,
                        api: authServices.socialAPI,
                        communityAPI: authServices.communityAPI,
                        photoAPI: authServices.photoAPI,
                        restaurantListAPI: authServices.restaurantListAPI,
                        interactionAPI: authServices.socialCollaborationAPI,
                        safetyAPI: authServices.releaseSafetyAPI,
                        onChange: { result in
                            if result.friendshipState != .friends {
                                cards.removeAll {
                                    $0.cacheScope == .friends &&
                                        $0.sourceUser?.userId == result.profile.userId
                                }
                            }
                            Task { await load(reset: true, preferCache: false) }
                        }
                    )
                }
            }
        }
    }

    @MainActor
    private func restoreAndLoad() async {
#if DEBUG
        if TasteMapUITestFixtures.usesDiscoveryFixture {
            authenticatedUser = AuthenticatedUserV1(id: TasteMapUITestFixtures.profileUserID, email: nil)
            initializeCityIfNeeded()
            if let override = TasteMapUITestFixtures.premiumOverride {
                _ = premiumEntitlementService.setDevelopmentOverride(override)
            }
            await premiumEntitlementService.activate(
                userID: TasteMapUITestFixtures.profileUserID,
                refreshFromServer: false
            )
            await load(reset: true, preferCache: true)
            return
        }
#endif
        authenticatedUser = await authServices.sessionManager.restoredUser()
        initializeCityIfNeeded()
        if let userID = authenticatedUser?.id {
            await premiumEntitlementService.activate(userID: userID)
        }
        await load(reset: true, preferCache: true)
    }

    @MainActor
    private func load(reset: Bool, preferCache: Bool) async {
        guard let userID = authenticatedUser?.id, !loading else { return }
        if reset { evidenceAvailability = nil }
        if mode == .similarTaste,
           premiumEntitlementService.access(for: .similarTaste) != .allowed {
            cards = []
            nextCursor = nil
            cacheDate = nil
            showingCache = false
            message = nil
            refreshIssue = nil
            return
        }
#if DEBUG
        if TasteMapUITestFixtures.usesDiscoveryFixture {
            if TasteMapUITestFixtures.visualQAMode == .error {
                cards = []
                nextCursor = nil
                cacheDate = nil
                showingCache = false
                message = "发现内容暂时无法加载，请检查网络后重试。"
                return
            }
            let page = TasteMapUITestFixtures.discoveryPage(mode: mode, window: trendWindowDays)
            cards = page.items.filter(\.isEligibleForDiscoveryPresentation)
            evidenceAvailability = page.evidenceAvailability
            nextCursor = nil
            cacheDate = .now.addingTimeInterval(-1800)
            showingCache = TasteMapUITestFixtures.usesDiscoveryOfflineFixture
                || TasteMapUITestFixtures.visualQAMode == .offline
            message = showingCache ? "当前显示上次缓存的内容。" : nil
            await establishDistanceAnchorIfNeeded()
            return
        }
#endif
        loading = reset
        message = nil
        refreshIssue = nil
        defer { loading = false }
        let window = mode == .trending ? trendWindowDays : 7
        let requestMode = mode
        let requestCity = city
        let cacheContext = ModelContext(modelContext.container)
        cacheContext.autosaveEnabled = false
        let store = LocalDiscoveryStore(context: cacheContext)
        let isCurrent = {
            authenticatedUser?.id == userID && accountScope.contains(ownerUserID: userID)
                && mode == requestMode && city == requestCity
                && (mode == .trending ? trendWindowDays : 7) == window
        }
        if reset && preferCache,
           let cached = try? store.cachedPage(mode: mode, city: city, currentUserID: userID,
                                               trendWindowDays: window) {
            cards = cached.cards.filter(\.isEligibleForDiscoveryPresentation); cacheDate = cached.updatedAt; showingCache = true; nextCursor = nil
        } else if reset {
            cards = []; nextCursor = nil; showingCache = false
        }
        var stage = TasteMapDiscoveryRefreshFailureStage.request
        do {
            let page = try await authServices.discoveryAPI.page(
                mode: mode, city: city, trendWindowDays: window, cursor: nil, limit: 20
            )
            guard isCurrent() else { return }
            stage = .cacheWrite
            try store.replaceCache(page: page, currentUserID: userID, trendWindowDays: window)
            cards = page.items.filter(\.isEligibleForDiscoveryPresentation)
            nextCursor = page.nextCursor
            cacheDate = LocalDiscoveryStoreDate.parse(page.generatedAt)
            showingCache = false
            if cards.isEmpty { message = emptyMessage(page.evidenceAvailability) }
            await establishDistanceAnchorIfNeeded()
        } catch {
            cacheContext.rollback()
            guard isCurrent() else { return }
            let issue = tasteMapDiscoveryRefreshIssue(error, stage: stage)
            refreshIssue = issue
            if issue.recoverable == false {
                cards = []; nextCursor = nil; cacheDate = nil; showingCache = false
                message = issue.message
                return
            }
            if cards.isEmpty,
                let cached = try? store.cachedPage(mode: mode, city: city, currentUserID: userID,
                                                   trendWindowDays: window) {
                cards = cached.cards.filter(\.isEligibleForDiscoveryPresentation); cacheDate = cached.updatedAt; showingCache = true; nextCursor = nil
            }
            showingCache = !cards.isEmpty
            nextCursor = nil
            message = issue.message + (cards.isEmpty ? "" : "正在显示上次缓存。")
        }
    }

    @MainActor
    private func loadMore() async {
        guard let userID = authenticatedUser?.id, let cursor = nextCursor,
              !loadingMore, !showingCache else { return }
        loadingMore = true
        defer { loadingMore = false }
        let window = mode == .trending ? trendWindowDays : 7
        do {
            let page = try await authServices.discoveryAPI.page(
                mode: mode, city: city, trendWindowDays: window, cursor: cursor, limit: 20
            )
            let existing = Set(cards.map(\.restaurant.globalKey))
            cards.append(contentsOf: page.items.filter {
                $0.isEligibleForDiscoveryPresentation && !existing.contains($0.restaurant.globalKey)
            })
            nextCursor = page.nextCursor
            try LocalDiscoveryStore(context: modelContext)
                .appendCache(page: page, currentUserID: userID, trendWindowDays: window)
        } catch {
            let issue = tasteMapDiscoveryRefreshIssue(error)
            refreshIssue = issue
            if !issue.recoverable { cards = []; nextCursor = nil; cacheDate = nil; showingCache = false }
            message = issue.message
        }
    }

    @MainActor
    private func addToWantToGo(_ card: DiscoveryCardV1) {
        guard card.viewerState == .none, authenticatedUser != nil else { return }
        do {
            let store = LocalDiscoveryStore(context: modelContext)
            guard let userID = authenticatedUser?.id else { return }
            let restaurant = try store.addToWantToGo(
                projection: card.restaurant,
                among: ownedRestaurants,
                currentUserID: userID
            )
            let state: DiscoveryViewerRestaurantStateV1 = restaurant.status == .visited ? .visited : .wantToGo
            updateViewerState(for: card.restaurant.globalKey, state: state)
            Task { await syncCoordinator.synchronizeNow() }
        } catch { message = "没有成功加入想吃，请稍后重试。" }
    }

    @MainActor
    private func addToRoulette(_ card: DiscoveryCardV1) {
        do {
            guard let userID = authenticatedUser?.id else { return }
            let restaurant = try LocalDiscoveryStore(context: modelContext)
                .addToWantToGo(
                    projection: card.restaurant,
                    among: ownedRestaurants,
                    currentUserID: userID
                )
            let state: DiscoveryViewerRestaurantStateV1 = restaurant.status == .visited ? .visited : .wantToGo
            updateViewerState(for: card.restaurant.globalKey, state: state)
            selectedRouletteRestaurantID = restaurant.id
            Task { await syncCoordinator.synchronizeNow() }
        } catch { message = "暂时无法加入轮盘，请稍后重试。" }
    }

    @MainActor
    private func updateViewerState(for globalKey: String, state: DiscoveryViewerRestaurantStateV1) {
        guard let userID = authenticatedUser?.id else { return }
        cards = cards.map { value in
            guard value.restaurant.globalKey == globalKey else { return value }
            var changed = value
            changed.viewerState = state
            return changed
        }
        try? LocalDiscoveryStore(context: modelContext).updateViewerState(
            globalKey: globalKey, currentUserID: userID, state: state
        )
        try? LocalCommunityStore(context: modelContext).updateViewerState(
            globalKey: globalKey, currentUserID: userID, state: state
        )
    }

    @MainActor
    private func initializeCityIfNeeded() {
        guard !didInitializeCity else { return }
        selectedCity = defaultCity
        didInitializeCity = true
    }

    @MainActor
    private func selectCity(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized != city else { return }
        selectedCity = normalized
        didInitializeCity = true
        distanceAnchor = nil
        distanceAnchorDescription = nil
        Task { await load(reset: true, preferCache: true) }
    }

    @MainActor
    private func resetFilters() {
        browseFilters.reset()
        distanceAnchor = nil
        distanceAnchorDescription = nil
    }

    @MainActor
    private func establishDistanceAnchorIfNeeded() async {
        guard mode == .forYou, browseFilters.needsDistanceAnchor else {
            distanceAnchorDescription = nil
            return
        }
        if distanceAnchor != nil { return }
#if DEBUG
        if TasteMapUITestFixtures.usesDiscoveryFixture,
           let fallback = DiscoveryBrowseResolver.centroid(of: cards) {
            distanceAnchor = fallback
            distanceAnchorDescription = "已按当前城市餐厅位置计算距离"
            return
        }
#endif
        do {
            let location = try await locationManager.requestCurrentLocation()
            distanceAnchor = DiscoveryBrowseCoordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            distanceAnchorDescription = "已按当前位置计算距离"
        } catch {
            if let fallback = DiscoveryBrowseResolver.centroid(of: cards) {
                distanceAnchor = fallback
                distanceAnchorDescription = city.isEmpty
                    ? "已按当前餐厅位置估算距离"
                    : "已按\(city)当前餐厅位置估算距离"
            } else {
                distanceAnchorDescription = "暂时无法取得距离基准"
            }
        }
    }

    private func emptyMessage(_ evidence: TasteMapDiscoveryEvidenceAvailabilityDTO?) -> String {
        if mode == .similarTaste {
            return evidence?.similarTasteEmptyMessage ?? TasteMapDiscoveryEvidenceAvailabilityDTO.unknownMessage
        }
        return city.isEmpty ? "先在个人资料设置城市，或记录一家餐厅。" : "这个城市暂时还没有可见的真实发现内容。"
    }
}

private enum LocalDiscoveryStoreDate {
    static func parse(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private enum DiscoveryFilterFocus: String, Identifiable {
    case all
    case sort
    case distance
    case rating

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "筛选推荐"
        case .sort: "排序"
        case .distance: "距离"
        case .rating: "社区评分"
        }
    }
}

struct DiscoveryContentView: View {
    @Binding var mode: DiscoveryModeV1
    @Binding var trendWindowDays: Int
    let cards: [DiscoveryCardV1]
    let unfilteredCardCount: Int
    let loading: Bool
    let loadingMore: Bool
    let message: String?
    var refreshIssue: TasteMapHybridBridgeErrorDTO? = nil
    let cacheDate: Date?
    let showingCache: Bool
    let isSignedIn: Bool
    var similarTasteAccess: PremiumAccessDecision = .allowed
    let city: String
    let availableCities: [String]
    @Binding var filters: DiscoveryBrowseFilters
    let filterEmptyReason: DiscoveryBrowseEmptyReason?
    let distanceAnchorDescription: String?
    let canLoadMore: Bool
    let onSelectCity: (String) -> Void
    let onResetFilters: () -> Void
    let onRetry: () -> Void
    let onOpenRestaurant: (DiscoveryCardV1) -> Void
    let onWantToGo: (DiscoveryCardV1) -> Void
    let onRecordVisit: (DiscoveryCardV1) -> Void
    let onAddToList: (DiscoveryCardV1) -> Void
    let onAddToRoulette: (DiscoveryCardV1) -> Void
    let onOpenUser: (DiscoveryPublicUserProjectionV1) -> Void
    let onLoadMore: () -> Void
    let photoAPI: (any PhotoBinaryAPI)?
    var showsModePicker = true
    var evidenceAvailability: TasteMapDiscoveryEvidenceAvailabilityDTO? = nil
    var onAddEvidence: (() -> Void)? = nil
    @State private var filterFocus: DiscoveryFilterFocus?
    @State private var enteringCity = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                if showsModePicker {
                    TasteMapSegmentedControl(
                        selection: $mode,
                        items: DiscoveryModeV1.allCases.map {
                            .init($0, title: $0.title)
                        },
                        accessibilityIdentifier: "discovery-mode-segment"
                    )
                }
                TasteMapFilterBar(accessibilityIdentifier: "discovery-filter-chip-strip") {
                    HStack(spacing: 8) {
                        DiscoveryCityMenu(
                            city: city,
                            availableCities: availableCities,
                            onSelect: onSelectCity,
                            onEnterAnother: { enteringCity = true }
                        )
                        if mode == .forYou {
                            TasteMapFilterChip(
                                title: "筛选",
                                semantic: .allFilters,
                                isActive: filters.activeCount > 0,
                                count: filters.activeCount,
                                accessibilityIdentifier: "discovery-filters"
                            ) { filterFocus = .all }

                            discoveryFilterChip(
                                focus: .sort,
                                title: filters.sort.title,
                                semantic: .sort,
                                isActive: filters.sort != .recommended,
                                identifier: "discovery-sort-chip"
                            )
                            discoveryFilterChip(
                                focus: .distance,
                                title: distanceChipTitle,
                                semantic: .distance,
                                isActive: filters.maximumDistanceKilometers != nil,
                                identifier: "discovery-distance-chip"
                            )
                            discoveryFilterChip(
                                focus: .rating,
                                title: ratingChipTitle,
                                semantic: .rating,
                                isActive: filters.minimumRating != nil,
                                identifier: "discovery-rating-chip"
                            )
                        }
                        if mode == .trending {
                            trendWindowChip(days: 7)
                            trendWindowChip(days: 30)
                        }
                    }
                }
                if showingCache, let cacheDate {
                    Label("缓存内容 · 更新于 \(TasteMapDisplayDate.relative(cacheDate))",
                          systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if mode == .forYou, let distanceAnchorDescription, filters.needsDistanceAnchor {
                    Label(distanceAnchorDescription, systemImage: "location.circle")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 8).padding(.bottom, 10)

            if !isSignedIn {
                TasteMapEmptyState(
                    title: "登录后发现",
                    message: "请先到“我的”使用 Apple 登录。",
                    systemImage: "person.crop.circle.badge.checkmark",
                    presentation: .embedded,
                    accessibilityIdentifier: "discovery-auth-empty-state"
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if DiscoveryContentAccessPolicy.blocksCards(mode: mode, access: similarTasteAccess) {
                if let refreshIssue {
                    TasteMapEmptyState(
                        title: refreshIssue.recoverable ? "发现内容暂未更新" : "暂时无法访问这部分发现内容",
                        message: refreshIssue.message,
                        systemImage: "exclamationmark.circle",
                        actionTitle: refreshIssue.recoverable ? "重试" : nil,
                        action: refreshIssue.recoverable ? onRetry : nil,
                        secondaryActionTitle: "为你推荐",
                        secondaryAction: { mode = .forYou },
                        presentation: .embedded,
                        accessibilityIdentifier: "discovery-access-error-state"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if similarTasteAccess == .loading {
                    ProgressView("正在确认同味权益…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    PremiumFeatureLockedView(feature: .similarTaste)
                }
            } else if loading && cards.isEmpty {
                ProgressView("正在寻找真实餐厅…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if cards.isEmpty {
                TasteMapEmptyState(
                    title: emptyStateTitle,
                    message: emptyStateMessage,
                    systemImage: filterEmptyReason == nil
                        ? (mode == .similarTaste ? "person.2.wave.2" : "fork.knife.circle")
                        : "line.3.horizontal.decrease.circle",
                    foodDiningVisualKind: filterEmptyReason == nil ? .genericDining : nil,
                    actionTitle: primaryEmptyActionTitle,
                    action: primaryEmptyAction,
                    secondaryActionTitle: filterEmptyReason != nil && canLoadMore
                        ? "继续加载更多结果" : offersEvidenceRecovery ? "为你推荐" : nil,
                    secondaryAction: filterEmptyReason != nil && canLoadMore ? onLoadMore : offersEvidenceRecovery ? { mode = .forYou } : nil,
                    presentation: .embedded,
                    accessibilityIdentifier: "discovery-content-empty-state"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if let message {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(cards) { card in
                            DiscoveryRestaurantCard(
                                card: card, onOpen: { onOpenRestaurant(card) },
                                onWantToGo: { onWantToGo(card) },
                                onRecordVisit: { onRecordVisit(card) },
                                onAddToList: { onAddToList(card) },
                                onAddToRoulette: { onAddToRoulette(card) },
                                onOpenUser: onOpenUser, photoAPI: photoAPI
                            )
                            .onAppear { if card.id == cards.last?.id { onLoadMore() } }
                        }
                        if loadingMore { ProgressView().padding() }
                        if canLoadMore && !loadingMore {
                            Button("加载更多", action: onLoadMore)
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("discovery-load-more")
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 120)
                }
            }
        }
        .sheet(item: $filterFocus) { focus in
            DiscoveryFilterSheet(filters: $filters, focus: focus)
        }
        .sheet(isPresented: $enteringCity) {
            DiscoveryCityEntrySheet(initialCity: city, onSelect: onSelectCity)
        }
    }

    private var emptyStateTitle: String {
        if let refreshIssue {
            return refreshIssue.recoverable ? "发现内容暂未更新" : "暂时无法访问这部分发现内容"
        }
        switch filterEmptyReason {
        case .locationUnavailable: return "暂时无法计算距离"
        case .filtersTooStrict: return "当前筛选没有结果"
        case nil: return mode == .similarTaste ? evidenceAvailability?.emptyTitle ?? "暂未找到可展示的同味推荐" : "暂时没有发现内容"
        }
    }

    private var offersEvidenceRecovery: Bool { mode == .similarTaste && refreshIssue == nil && filterEmptyReason == nil }
    private var primaryEmptyActionTitle: String? {
        if refreshIssue?.recoverable == false { return nil }
        if filterEmptyReason != nil { return "重置筛选" }
        if offersEvidenceRecovery {
            if evidenceAvailability?.recoveryAction == "record", onAddEvidence != nil { return "补充到访与评分" }
            if evidenceAvailability?.recoveryAction == "city" { return "切换城市" }
        }
        return "重试"
    }
    private var primaryEmptyAction: (() -> Void)? {
        if refreshIssue?.recoverable == false { return nil }
        if filterEmptyReason != nil { return onResetFilters }
        if offersEvidenceRecovery {
            if evidenceAvailability?.recoveryAction == "record", let onAddEvidence { return onAddEvidence }
            if evidenceAvailability?.recoveryAction == "city" { return { enteringCity = true } }
        }
        return onRetry
    }

    private var emptyStateMessage: String {
        if let refreshIssue { return refreshIssue.message }
        switch filterEmptyReason {
        case .locationUnavailable: return "允许定位，或等待当前城市餐厅加载后再试。"
        case .filtersTooStrict: return "已加载 \(unfilteredCardCount) 家真实餐厅；可以重置筛选或继续加载。"
        case nil: return message ?? "换个时间再来看看。"
        }
    }

    private var distanceChipTitle: String {
        filters.maximumDistanceKilometers.map { "距离 \(Int($0)) km" } ?? "距离"
    }

    private var ratingChipTitle: String {
        filters.minimumRating.map { String(format: "餐厅评分 %.1f+", $0 * 2) } ?? "餐厅评分"
    }

    private func discoveryFilterChip(
        focus: DiscoveryFilterFocus,
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
        ) { filterFocus = focus }
    }

    private func trendWindowChip(days: Int) -> some View {
        TasteMapFilterChip(
            title: "近 \(days) 天",
            semantic: .timeWindow,
            isActive: trendWindowDays == days,
            accessibilityIdentifier: "discovery-trend-window-\(days)"
        ) { trendWindowDays = days }
    }
}

private struct DiscoveryCityMenu: View {
    let city: String
    let availableCities: [String]
    let onSelect: (String) -> Void
    let onEnterAnother: () -> Void

    var body: some View {
        Menu {
            Button("自动选择范围", systemImage: city.isEmpty ? "checkmark" : "sparkles") {
                onSelect("")
            }
            if !availableCities.isEmpty { Divider() }
            ForEach(availableCities, id: \.self) { value in
                Button {
                    onSelect(value)
                } label: {
                    if value == city { Label(value, systemImage: "checkmark") }
                    else { Text(value) }
                }
            }
            Divider()
            Button("输入其他城市…", systemImage: "square.and.pencil", action: onEnterAnother)
        } label: {
            TasteMapFilterChipLabel(
                title: city.isEmpty ? "自动范围" : city,
                semantic: .city,
                isActive: !city.isEmpty
            )
        }
        .buttonStyle(.plain)
        .frame(minHeight: TasteMapDesignTokens.Control.minimumHitTarget)
        .accessibilityIdentifier("discovery-city-menu")
    }
}

private struct DiscoveryCityEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var city: String
    let onSelect: (String) -> Void

    init(initialCity: String, onSelect: @escaping (String) -> Void) {
        _city = State(initialValue: initialCity)
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例如：杭州", text: $city)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("discovery-city-field")
                } header: {
                    Text("浏览城市")
                } footer: {
                    Text("城市只用于限定发现内容，不会修改你的个人资料。清空后由服务端根据个人资料和最近记录自动确定范围。")
                }
            }
            .navigationTitle("切换城市")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        onSelect(city)
                        dismiss()
                    }
                    .accessibilityIdentifier("discovery-city-apply")
                }
            }
        }
    }
}

private struct DiscoveryFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filters: DiscoveryBrowseFilters
    let focus: DiscoveryFilterFocus

    var body: some View {
        NavigationStack {
            Form {
                if focus == .all || focus == .sort {
                    Section("排序") {
                    Picker("推荐排序", selection: $filters.sort) {
                        ForEach(DiscoveryBrowseSort.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("discovery-sort")
                    }
                }
                if focus == .all || focus == .distance {
                    Section {
                    Picker("最远距离", selection: $filters.maximumDistanceKilometers) {
                        Text("不限").tag(Double?.none)
                        ForEach([1.0, 3.0, 5.0, 10.0], id: \.self) { value in
                            Text("\(Int(value)) km 内").tag(Double?.some(value))
                        }
                    }
                    .accessibilityIdentifier("discovery-distance")
                } header: {
                    Text("距离")
                } footer: {
                    Text("距离排序会优先使用当前位置；定位不可用时，使用当前城市已加载餐厅的中心位置估算。")
                    }
                }
                if focus == .all || focus == .rating {
                    Section {
                    Picker("最低评分", selection: $filters.minimumRating) {
                        Text("不限评分").tag(Double?.none)
                        ForEach(TasteMapRatingFilterOptions.discoveryThresholdsOutOfTen, id: \.self) { score in
                            Text(TasteMapRatingFilterOptions.label(for: score)).tag(Double?.some(score / 2))
                        }
                    }
                    .accessibilityIdentifier("discovery-rating")
                } header: {
                    Text("社区评分")
                } footer: {
                    Text("评分来自当前可见的真实社区样本；没有评分的餐厅不会通过最低评分筛选。")
                    }
                }
            }
            .navigationTitle(focus.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("重置", action: resetFocusedValue)
                        .disabled(!focusedValueIsActive)
                        .accessibilityIdentifier("discovery-filter-reset")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("discovery-filter-done")
                }
            }
        }
    }

    private var focusedValueIsActive: Bool {
        switch focus {
        case .all: filters.activeCount > 0
        case .sort: filters.sort != .recommended
        case .distance: filters.maximumDistanceKilometers != nil
        case .rating: filters.minimumRating != nil
        }
    }

    private func resetFocusedValue() {
        switch focus {
        case .all: filters.reset()
        case .sort: filters.sort = .recommended
        case .distance: filters.maximumDistanceKilometers = nil
        case .rating: filters.minimumRating = nil
        }
    }
}

struct DiscoveryRestaurantQuickActions: View {
    let viewerState: DiscoveryViewerRestaurantStateV1
    let onRecordVisit: () -> Void
    let onWantToGo: () -> Void
    let onAddToList: () -> Void
    let onAddToRoulette: () -> Void
    let identifierPrefix: String
    let restaurantKey: String

    var body: some View {
        HStack(spacing: 0) { actions }
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private var actions: some View {
        circularAction("记录到访", systemImage: "plus", action: onRecordVisit)
            .accessibilityIdentifier("\(identifierPrefix)-record-\(restaurantKey)")
            .contextMenu {
                Button("加入我的食单", systemImage: "list.number", action: onAddToList)
            }
        if viewerState == .none {
            circularAction("加入想吃", systemImage: "bookmark", action: onWantToGo)
                .accessibilityIdentifier("\(identifierPrefix)-want-\(restaurantKey)")
        } else {
            circularAction(
                viewerState == .visited ? "已去过" : "已想吃",
                systemImage: "bookmark.fill",
                selected: true,
                action: onWantToGo
            )
            .disabled(true)
        }
        circularAction("加入转盘", systemImage: "dice", action: onAddToRoulette)
            .accessibilityIdentifier("\(identifierPrefix)-roulette-\(restaurantKey)")
    }

    private func circularAction(
        _ title: String,
        systemImage: String,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if systemImage == "dice" { TasteMapDiceActionGlyph().frame(width: TasteMapDesignTokens.Icon.standard, height: TasteMapDesignTokens.Icon.standard) }
                else { Image(systemName: systemImage) }
            }
                .font(.system(size: TasteMapDesignTokens.Icon.standard, weight: .regular))
                .foregroundStyle(TasteMapCoreTheme.brandDeep)
                .frame(width: TasteMapDesignTokens.Activity.restaurantActionDiameter, height: TasteMapDesignTokens.Activity.restaurantActionDiameter)
                .background(selected ? TasteMapCoreTheme.brandSoft : TasteMapCoreTheme.surface, in: Circle())
                .overlay { Circle().stroke(TasteMapCoreTheme.border, lineWidth: TasteMapDesignTokens.Border.standard) }
                .frame(width: TasteMapDesignTokens.Control.minimumHitTarget, height: TasteMapDesignTokens.Control.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct DiscoveryRestaurantCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let card: DiscoveryCardV1
    let onOpen: () -> Void
    let onWantToGo: () -> Void
    let onRecordVisit: () -> Void
    let onAddToList: () -> Void
    let onAddToRoulette: () -> Void
    let onOpenUser: (DiscoveryPublicUserProjectionV1) -> Void
    let photoAPI: (any PhotoBinaryAPI)?

    var body: some View {
        TasteMapActivityCard {
            VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Button(action: onOpen) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(card.restaurant.name).font(.headline).foregroundStyle(.primary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text([card.restaurant.city, card.restaurant.address].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("discovery-open-\(card.restaurant.globalKey)")
                        Spacer()
                        if card.mode == .forYou {
                            TasteMapRecommendationSignalView(matchPercent: card.personalTastePercent, probability: card.calibratedLikeProbability)
                        } else {
                            FoodDiningVisualIcon(
                            kind: FoodDiningVisualLibrary.kind(
                                legacySymbol: card.restaurant.markerEmoji
                            ),
                            usage: .decorative,
                            size: 34
                            )
                        }
                    }
                    if card.mode == .similarTaste {
                        PublicContentActivityMedia(presentation: .init(card: card), restaurantName: card.restaurant.name,
                                                   tags: card.restaurant.tags, semanticID: card.id, photoAPI: photoAPI,
                                                   onOpenRestaurant: onOpen)
                    } else {
                    Button(action: onOpen) { DiscoveryRestaurantImage(restaurant: card.restaurant, photoAPI: photoAPI)
                        .frame(
                            width: TasteMapDesignTokens.Layout.socialFeedMediaWidth,
                            height: TasteMapDesignTokens.Layout.socialFeedMediaWidth
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                    }
            }
            recommendationReasons
            if let similarity = card.displayableSimilarity {
                Label(
                    "同味度 \(similarity.percent)% · 基于 \(similarity.sharedRestaurantCount) 家共同评分餐厅",
                    systemImage: "person.2.wave.2"
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { attributionContent }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 10) {
                    if let source = card.sourceUser {
                        sourceButton(source)
                    }
                    Spacer()
                    activityRating
                }
            }
            if let trend = card.trend {
                Label(
                    "近 \(trend.windowDays) 天 · \(trend.uniqueVisitorCount) 人到访",
                    systemImage: "flame.fill"
                )
                .font(.caption)
                .foregroundStyle(TasteMapCoreTheme.textSecondary)
            }
            if card.mode == .forYou {
                RestaurantNotInterestedButton(restaurantID: card.restaurant.globalKey)
            }
            DiscoveryRestaurantQuickActions(
                viewerState: card.viewerState,
                onRecordVisit: onRecordVisit,
                onWantToGo: onWantToGo,
                onAddToList: onAddToList,
                onAddToRoulette: onAddToRoulette,
                identifierPrefix: "discovery",
                restaurantKey: card.restaurant.globalKey
            )
            }
        }
    }

    @ViewBuilder
    private var attributionContent: some View {
        if let source = card.sourceUser {
            sourceButton(source)
        }
        activityRating
    }

    private func sourceButton(_ source: DiscoveryPublicUserProjectionV1) -> some View {
        Button { onOpenUser(source) } label: {
            HStack(spacing: 7) {
                PresetProfileAvatarView(preset: source.avatarPresetId)
                    .frame(width: 28, height: 28).clipShape(Circle())
                Text(source.displayName)
                    .font(.caption.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private var activityRating: some View {
        if let activity = card.activity {
            TasteMapActivityRatingBadge(
                rating: activity.rating,
                accessibilityIdentifier: "discovery-activity-rating-\(card.restaurant.globalKey)"
            )
        }
    }

    @ViewBuilder private var recommendationReasons: some View {
        if !card.reasons.isEmpty {
            TasteMapRecommendationReasons(reasons: card.reasons.map(\.text))
                .accessibilityIdentifier("discovery-reasons-\(card.restaurant.globalKey)")
        }
    }
}

struct DiscoveryRestaurantImage: View {
    let restaurant: DiscoveryRestaurantProjectionV1
    let photoAPI: (any PhotoBinaryAPI)?
    var allowsMerchantImageFallback = true

    var body: some View {
        TasteMapRestaurantImage(
            resolution: RestaurantImagePriorityPolicy.resolution(
                localUserPhotoID: nil,
                publicOrCachedPhotoID: restaurant.photo?.isActualDiningPhoto == true ? restaurant.photo?.photoId : nil,
                providerMerchantImageURL: nil as String?
            ),
            photoAPI: photoAPI,
            semanticID: restaurant.globalKey,
            fallbackKind: FoodDiningVisualLibrary.kind(legacySymbol: restaurant.markerEmoji),
            fallbackBackgroundColor: Color.accentColor.opacity(0.14),
            fallbackIconSize: 64,
            categoryVisualID: FoodCategoryVisualResolver.resolve(name: restaurant.name, tags: restaurant.tags),
            foodLibraryArtwork: .init(name: restaurant.name, tags: restaurant.tags,
                                      categoryVisualID: FoodCategoryVisualResolver.resolve(name: restaurant.name, tags: restaurant.tags)),
            accessibilityLabel: "\(restaurant.name)餐厅图片"
        )
    }
}

struct DiscoveryRestaurantDestination: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Environment(\.localAccountScope) private var accountScope
    @Query private var profiles: [UserProfile]
    let card: DiscoveryCardV1
    let restaurants: [Restaurant]
    let onWantToGo: () -> Void
    var onViewerStateChange: (DiscoveryViewerRestaurantStateV1) -> Void = { _ in }
    let photoAPI: (any PhotoBinaryAPI)?
    var entrySource: RestaurantDetailEntrySource = .discovery
    @State private var addingToList = false
    @State private var recordingVisit = false
    @State private var rouletteRestaurantID: UUID?
    @State private var actionMessage: String?
    @State private var navigationError: String?
    @State private var viewerState: DiscoveryViewerRestaurantStateV1

    init(
        card: DiscoveryCardV1,
        restaurants: [Restaurant],
        onWantToGo: @escaping () -> Void,
        onViewerStateChange: @escaping (DiscoveryViewerRestaurantStateV1) -> Void = { _ in },
        photoAPI: (any PhotoBinaryAPI)?,
        entrySource: RestaurantDetailEntrySource = .discovery
    ) {
        self.card = card
        self.restaurants = restaurants
        self.onWantToGo = onWantToGo
        self.onViewerStateChange = onViewerStateChange
        self.photoAPI = photoAPI
        self.entrySource = entrySource
        _viewerState = State(initialValue: card.viewerState)
    }

    private var currentUserID: String? {
        accountScope.authenticatedUserID
    }

    private var ownedRestaurants: [Restaurant] {
        restaurants.filter { accountScope.contains(ownerUserID: $0.ownerUserID) }
    }

    var body: some View {
        if let local = LocalDiscoveryStore(context: modelContext)
            .localRestaurant(for: card.restaurant, among: ownedRestaurants) {
            RestaurantDetailView(restaurant: local, entrySource: entrySource)
        } else {
            NavigationStack {
                ScrollView {
                    RestaurantDetailStandardBody {
                        DiscoveryRestaurantImage(restaurant: card.restaurant, photoAPI: photoAPI)
                            .frame(height: 216)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .accessibilityIdentifier("restaurant-photo-gallery")
                    } header: {
                        RestaurantDetailHeader(identity: remoteIdentity)
                    } actions: {
                        RestaurantQuickActionsSection(
                            restaurantAddress: card.restaurant.address,
                            status: remoteIdentity.status,
                            publicShareEntityID: "",
                            canPublicShare: false,
                            showsShareAvailabilityHint: false,
                            canRecordVisit: currentUserID != nil,
                            canMarkWantToGo: currentUserID != nil && viewerState == .none,
                            canEdit: false,
                            canAddToList: currentUserID != nil,
                            canAddToRoulette: currentUserID != nil,
                            identifiers: .discoveryDetail(restaurantKey: card.restaurant.globalKey),
                            onRecordVisit: { recordingVisit = true },
                            onMarkWantToGo: markRemoteWantToGo,
                            onEdit: {},
                            onAddToList: { addingToList = true },
                            onAddToRoulette: addToRoulette,
                            onCopyName: { UIPasteboard.general.string = card.restaurant.name },
                            onCopyAddress: { UIPasteboard.general.string = card.restaurant.address }
                        )
                    } business: {
                        if remoteMetadata.hasBusinessInformation {
                            RestaurantBusinessInformationSection(metadata: remoteMetadata, onCall: {})
                        }
                    } location: {
                        RestaurantLocationSection(
                            projection: card.restaurant,
                            onOpenAppleMaps: openRemoteInAppleMaps
                        )
                    } ratings: {
                        if !remoteRatingReferences.isEmpty {
                            RestaurantRatingReferencesSection(references: remoteRatingReferences)
                        }
                    } userPhotos: {
                        RestaurantUserPhotosSection(hasPhotos: card.restaurant.photo != nil) {
                            DiscoveryRestaurantImage(
                                restaurant: card.restaurant,
                                photoAPI: photoAPI,
                                allowsMerchantImageFallback: false
                            )
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    } personalOverview: {
                        RestaurantDetailStatsSection(
                            remoteMessage: "只有你明确记录到访后，才会创建并显示属于你的餐厅记录。"
                        )
                    } history: {
                        RestaurantVisitHistorySection(
                            visits: [], companionNamesByID: [:], sourceNamesByID: [:],
                            onEdit: { _ in }, onDelete: { _ in }
                        )
                    } context: {
                        RestaurantDiscoveryContextSection(
                            context: DiscoveryCachedCardContext(card: card)
                        )
                    } extended: {
                        if let actionMessage {
                            Text(actionMessage).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .background(TasteMapCoreTheme.page)
                .navigationTitle("餐厅详情")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                }
                .safeAreaInset(edge: .bottom) {
                    Button { recordingVisit = true } label: {
                        Label("记录到访", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(currentUserID == nil)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.bar)
                    .accessibilityIdentifier("restaurant-detail-add-visit")
                }
                .sheet(isPresented: $addingToList) {
                    if let currentUserID {
                        AddPlaceToListsSheet(place: card.restaurant, currentUserID: currentUserID)
                    }
                }
                .sheet(isPresented: $recordingVisit) {
                    VisitEditorView(
                        candidate: card.restaurant.restaurantCandidate,
                        onVisitSaved: { _ in
                            viewerState = .visited
                            onViewerStateChange(.visited)
                            Task { await syncCoordinator.synchronizeNow() }
                        }
                    )
                }
                .sheet(isPresented: Binding(
                    get: { rouletteRestaurantID != nil },
                    set: { if !$0 { rouletteRestaurantID = nil } }
                )) {
                    NavigationStack {
                        RestaurantRouletteScreen(
                            preferredCity: card.restaurant.city,
                            initialRestaurantID: rouletteRestaurantID
                        )
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("完成") { rouletteRestaurantID = nil }
                            }
                        }
                    }
                }
                .alert("无法打开 Apple Maps", isPresented: Binding(
                    get: { navigationError != nil },
                    set: { if !$0 { navigationError = nil } }
                )) {
                    Button("好", role: .cancel) { navigationError = nil }
                } message: {
                    Text(navigationError ?? "请稍后重试。")
                }
            }
        }
    }

    private var remoteIdentity: RestaurantDetailIdentityPresentation {
        RestaurantDetailIdentityPresentation(
            projection: card.restaurant,
            viewerState: viewerState
        )
    }

    private var remoteMetadata: RestaurantDetailMetadata {
        RestaurantDetailMetadata(projection: card.restaurant)
    }

    private var remoteRatingReferences: [RestaurantRatingReference] {
        [
            remoteRatingReference("我的评分", card.ratings.mine, "star.fill"),
            remoteRatingReference("全部用户评分", card.ratings.community, "person.3.fill"),
            remoteRatingReference("好友评分", card.ratings.friends, "person.2.fill"),
            remoteRatingReference("同味评分", card.ratings.similarTaste, "person.2.wave.2.fill"),
        ].compactMap { $0 }
    }

    private func remoteRatingReference(
        _ title: String,
        _ rating: DiscoveryRatingProjectionV1,
        _ systemImage: String
    ) -> RestaurantRatingReference? {
        guard let value = rating.value, value.isFinite, (0...5).contains(value),
              rating.sampleCount > 0 else { return nil }
        return RestaurantRatingReference(
            title: title, value: value,
            sampleCount: rating.sampleCount, systemImage: systemImage
        )
    }

    @MainActor
    private func markRemoteWantToGo() {
        guard currentUserID != nil, viewerState == .none else { return }
        onWantToGo()
        viewerState = .wantToGo
        onViewerStateChange(.wantToGo)
    }

    @MainActor
    private func openRemoteInAppleMaps() {
        let projectedRestaurant = Restaurant(
            ownerUserID: LocalAccountOwner.legacyQuarantine,
            name: card.restaurant.name,
            address: card.restaurant.address,
            latitude: card.restaurant.latitude,
            longitude: card.restaurant.longitude,
            appleMapItemIdentifier: card.restaurant.placeIdentities
                .first(where: { $0.provider == .appleMaps })?.externalId,
            city: card.restaurant.city,
            status: viewerState == .visited ? .visited : .wantToGo,
            remoteID: card.restaurant.globalKey,
            syncStatus: .synced
        )
        if !AppleMapsRestaurantNavigator().openInAppleMaps(projectedRestaurant) {
            navigationError = "系统没有成功打开这家餐厅的位置。"
        }
    }

    @MainActor
    private func addToRoulette() {
        do {
            let restaurant = try LocalDiscoveryStore(context: modelContext).addToWantToGo(
                projection: card.restaurant,
                among: ownedRestaurants,
                currentUserID: currentUserID ?? LocalAccountOwner.guest
            )
            let state: DiscoveryViewerRestaurantStateV1 = restaurant.status == .visited ? .visited : .wantToGo
            viewerState = state
            onViewerStateChange(state)
            rouletteRestaurantID = restaurant.id
            Task { await syncCoordinator.synchronizeNow() }
        } catch {
            actionMessage = "暂时无法加入轮盘，请稍后重试。"
        }
    }
}
