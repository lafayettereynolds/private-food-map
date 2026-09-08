import SwiftData
import SwiftUI
import UIKit

struct CommunityFeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NativeAuthServices.self) private var authServices
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Query private var restaurants: [Restaurant]
    let showsScopePicker: Bool
    let showsNavigationTitle: Bool

    @State private var scope: CommunityFeedScopeV1
    @State private var currentUserID: String?
    @State private var items: [PublicContentItemV1] = []
    @State private var nextCursor: String?
    @State private var loading = false
    @State private var loadingMore = false
    @State private var message: String?
    @State private var showingCache = false
    @State private var selectedItem: PublicContentItemV1?
    @State private var selectedUser: PublicContentUserV1?
    @State private var selectedVisitItem: PublicContentItemV1?
    @State private var selectedListItem: PublicContentItemV1?
    @State private var selectedRouletteRestaurantID: UUID?

    init(
        initialScope: CommunityFeedScopeV1 = .following,
        showsScopePicker: Bool = true,
        showsNavigationTitle: Bool = true
    ) {
        self.showsScopePicker = showsScopePicker
        self.showsNavigationTitle = showsNavigationTitle
        _scope = State(initialValue: initialScope)
    }

    private var ownedRestaurants: [Restaurant] {
        guard let currentUserID else { return [] }
        return restaurants.filter { $0.ownerUserID == currentUserID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if currentUserID == nil && !loading {
                    TasteMapEmptyState(
                        title: "登录后查看社区",
                        message: "请先到“我的”使用 Apple 登录。",
                        systemImage: "person.crop.circle.badge.checkmark",
                        presentation: .embedded,
                        accessibilityIdentifier: "community-auth-empty-state"
                    )
                } else if loading && items.isEmpty {
                    ProgressView("正在加载社区动态…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty {
                    TasteMapEmptyState(
                        title: scope == .following ? "还没有关注动态" : "还没有公开动态",
                        message: message ?? (scope == .following
                            ? "关注用户或添加好友后，他们允许你查看的新记录会出现在这里。"
                            : "有新的公开到访记录后会显示在这里。"),
                        systemImage: scope == .following ? "person.2" : "clock",
                        foodDiningVisualKind: .sharedMeal,
                        actionTitle: "重试",
                        action: { Task { await load(reset: true, preferCache: false) } },
                        presentation: .embedded,
                        accessibilityIdentifier: "community-content-empty-state"
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if showingCache {
                                Label("离线或网络不可用，当前显示最近缓存的公开内容。", systemImage: "wifi.slash")
                                    .font(.footnote).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if let message {
                                Text(message).font(.footnote).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ForEach(items) { item in
                                PublicContentCard(
                                    item: item,
                                    photoAPI: authServices.photoAPI,
                                    onOpenRestaurant: { selectedItem = item },
                                    onOpenUser: { selectedUser = item.user },
                                    onWantToGo: { addToWantToGo(item) },
                                    onRecordVisit: { selectedVisitItem = item },
                                    onAddToList: { selectedListItem = item },
                                    onAddToRoulette: { addToRoulette(item) },
                                    interactionAPI: authServices.socialCollaborationAPI,
                                    safetyAPI: authServices.releaseSafetyAPI,
                                    currentUserID: currentUserID,
                                    onEngagementChange: { updateEngagement(itemID: item.id, engagement: $0) },
                                    onBlocked: { blockDidComplete(userID: item.user.userId) }
                                )
                                .onAppear { if item.id == items.last?.id { Task { await loadMore() } } }
                            }
                            if loadingMore { ProgressView().padding() }
                        }
                        .padding(.horizontal, 16).padding(.bottom, 120)
                    }
                }
            }
            .navigationTitle(showsNavigationTitle ? "社区" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(showsNavigationTitle ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                if showsScopePicker {
                    ToolbarItem(placement: .principal) {
                        TasteMapSegmentedControl(
                            selection: $scope,
                            items: CommunityFeedScopeV1.allCases.map {
                                .init($0, title: $0.title)
                            },
                            accessibilityIdentifier: "community-scope-segment"
                        )
                        .frame(width: 190)
                    }
                }
            }
            .background(TasteMapCoreTheme.page)
            .refreshable { await load(reset: true, preferCache: false) }
            .task { await restoreAndLoad() }
            .onChange(of: scope) { _, _ in Task { await load(reset: true, preferCache: true) } }
            .sheet(item: $selectedItem) { item in
                DiscoveryRestaurantDestination(
                    card: item.discoveryCard, restaurants: ownedRestaurants,
                    onWantToGo: { addToWantToGo(item) },
                    onViewerStateChange: {
                        updateViewerState(globalKey: item.restaurant.globalKey, state: $0)
                    },
                    photoAPI: authServices.photoAPI,
                    entrySource: .community
                )
            }
            .sheet(item: $selectedVisitItem) { item in
                VisitEditorView(
                    candidate: item.restaurant.discoveryProjection.restaurantCandidate,
                    onVisitSaved: { _ in
                        updateViewerState(globalKey: item.restaurant.globalKey, state: .visited)
                        Task { await syncCoordinator.synchronizeNow() }
                    }
                )
            }
            .sheet(item: $selectedListItem) { item in
                if let currentUserID {
                    AddPlaceToListsSheet(
                        place: item.restaurant.discoveryProjection,
                        currentUserID: currentUserID
                    )
                }
            }
            .sheet(isPresented: Binding(
                get: { selectedRouletteRestaurantID != nil },
                set: { if !$0 { selectedRouletteRestaurantID = nil } }
            )) {
                NavigationStack {
                    RestaurantRouletteScreen(initialRestaurantID: selectedRouletteRestaurantID)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("完成") { selectedRouletteRestaurantID = nil }
                            }
                        }
                }
            }
            .sheet(item: $selectedUser) { user in
                if let currentUserID {
                    SocialPublicProfileView(
                        initial: user.socialResult, currentUserID: currentUserID,
                        api: authServices.socialAPI, communityAPI: authServices.communityAPI,
                        photoAPI: authServices.photoAPI,
                        restaurantListAPI: authServices.restaurantListAPI,
                        interactionAPI: authServices.socialCollaborationAPI,
                        safetyAPI: authServices.releaseSafetyAPI,
                        onChange: { result in
                            if result.friendshipState != .friends
                                || (scope == .following && !result.isFollowing) {
                                items.removeAll { $0.cacheScope == .friends && $0.user.userId == result.profile.userId }
                                if scope == .following && !result.isFollowing {
                                    items.removeAll { $0.user.userId == result.profile.userId }
                                }
                                try? LocalCommunityStore(context: modelContext)
                                    .invalidateOwner(result.profile.userId, currentUserID: currentUserID)
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
        if TasteMapUITestFixtures.usesCommunityFixture {
            currentUserID = TasteMapUITestFixtures.profileUserID
            let fixture = TasteMapUITestFixtures.communityPage(scope: scope)
            items = fixture.items.filter(\.isEligibleForDiscoveryFeed)
            nextCursor = fixture.nextCursor
            showingCache = TasteMapUITestFixtures.usesCommunityOfflineFixture
            return
        }
#endif
        currentUserID = await authServices.sessionManager.restoredUser()?.id
        await load(reset: true, preferCache: true)
    }

    @MainActor
    private func load(reset: Bool, preferCache: Bool) async {
        guard let currentUserID, !loading else { return }
        let route = LocalCommunityStore.feedRoute(scope)
        if reset {
            if preferCache, let cached = try? LocalCommunityStore(context: modelContext)
                .cached(currentUserID: currentUserID, routeKey: route) {
                items = cached.items.filter(\.isEligibleForDiscoveryFeed)
                showingCache = true
                nextCursor = nil
            } else {
                items = []
                showingCache = false
                nextCursor = nil
            }
        }
        loading = true; defer { loading = false }
        do {
            let page = try await authServices.communityAPI.feed(scope: scope, cursor: nil, limit: 20)
            items = page.items.filter(\.isEligibleForDiscoveryFeed)
            nextCursor = page.nextCursor
            showingCache = false
            message = nil
            try LocalCommunityStore(context: modelContext).replace(
                items: page.items, currentUserID: currentUserID, routeKey: route,
                fetchedAt: CachedCommunityContent.date(page.generatedAt) ?? .now
            )
        } catch {
            if items.isEmpty, let cached = try? LocalCommunityStore(context: modelContext)
                .cached(currentUserID: currentUserID, routeKey: route) {
                items = cached.items.filter(\.isEligibleForDiscoveryFeed); showingCache = true; nextCursor = nil
            }
            message = items.isEmpty ? "社区内容暂时无法加载，请稍后重试。" : "刷新失败，继续显示已有缓存。"
        }
    }

    @MainActor
    private func loadMore() async {
        guard let currentUserID, let cursor = nextCursor, !loadingMore, !showingCache else { return }
        loadingMore = true; defer { loadingMore = false }
        do {
            let page = try await authServices.communityAPI.feed(scope: scope, cursor: cursor, limit: 20)
            items = deduplicated(items + page.items.filter(\.isEligibleForDiscoveryFeed))
            nextCursor = page.nextCursor
            try LocalCommunityStore(context: modelContext).append(
                items: page.items, currentUserID: currentUserID,
                routeKey: LocalCommunityStore.feedRoute(scope),
                fetchedAt: CachedCommunityContent.date(page.generatedAt) ?? .now
            )
        } catch { message = "加载更多失败，请稍后重试。" }
    }

    @MainActor
    private func addToWantToGo(_ item: PublicContentItemV1) {
        guard item.viewerState == .none, let currentUserID else { return }
        do {
            let restaurant = try LocalDiscoveryStore(context: modelContext).addToWantToGo(
                projection: item.restaurant.discoveryProjection,
                among: ownedRestaurants,
                currentUserID: currentUserID
            )
            updateViewerState(
                globalKey: item.restaurant.globalKey,
                state: restaurant.status == .visited ? .visited : .wantToGo
            )
            Task { await syncCoordinator.synchronizeNow() }
        } catch { message = "暂时无法加入想吃，请稍后重试。" }
    }

    @MainActor
    private func addToRoulette(_ item: PublicContentItemV1) {
        guard let currentUserID else { return }
        do {
            let restaurant = try LocalDiscoveryStore(context: modelContext).addToWantToGo(
                projection: item.restaurant.discoveryProjection,
                among: ownedRestaurants,
                currentUserID: currentUserID
            )
            updateViewerState(
                globalKey: item.restaurant.globalKey,
                state: restaurant.status == .visited ? .visited : .wantToGo
            )
            selectedRouletteRestaurantID = restaurant.id
            Task { await syncCoordinator.synchronizeNow() }
        } catch { message = "暂时无法加入轮盘，请稍后重试。" }
    }

    @MainActor
    private func blockDidComplete(userID: String) {
        guard let currentUserID else { return }
        items.removeAll { $0.user.userId == userID }
        try? LocalCommunityStore(context: modelContext)
            .invalidateOwner(userID, currentUserID: currentUserID)
        selectedUser = nil
        message = "已屏蔽该用户。"
    }

    @MainActor
    private func updateViewerState(
        globalKey: String,
        state: DiscoveryViewerRestaurantStateV1
    ) {
        for index in items.indices where items[index].restaurant.globalKey == globalKey {
            items[index].viewerState = state
        }
        guard let currentUserID else { return }
        try? LocalCommunityStore(context: modelContext).updateViewerState(
            globalKey: globalKey, currentUserID: currentUserID, state: state
        )
        try? LocalDiscoveryStore(context: modelContext).updateViewerState(
            globalKey: globalKey, currentUserID: currentUserID, state: state
        )
    }

    private func deduplicated(_ values: [PublicContentItemV1]) -> [PublicContentItemV1] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }
    }

    private func updateEngagement(itemID: String, engagement: CommunityEngagementSummaryV1) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].engagement = engagement
    }
}

struct PublicContentCard: View {
    let item: PublicContentItemV1
    let photoAPI: (any PhotoBinaryAPI)?
    let onOpenRestaurant: () -> Void
    let onOpenUser: () -> Void
    let onWantToGo: () -> Void
    let onRecordVisit: () -> Void
    let onAddToList: () -> Void
    let onAddToRoulette: () -> Void
    var interactionAPI: (any CommunityInteractionAPI)? = nil
    var safetyAPI: (any ReleaseSafetyAPI)? = nil
    var currentUserID: String? = nil
    var onEngagementChange: ((CommunityEngagementSummaryV1) -> Void)? = nil
    var onBlocked: (() -> Void)? = nil

    var body: some View {
        TasteMapActivityCard {
            VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: TasteMapDesignTokens.Spacing.xSmall) {
            Button(action: onOpenUser) {
                HStack(spacing: 10) {
                    PresetProfileAvatarView(preset: item.user.avatarPresetId)
                        .frame(width: 42, height: 42).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.user.displayName).font(.headline).foregroundStyle(.primary).lineLimit(2)
                        Text(eventText).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if item.cacheScope == .friends {
                        Label("好友可见", systemImage: "person.2.fill")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }.buttonStyle(.plain)

                CommunityContentMoreMenu(
                    visitID: item.visit?.id, authorUserID: item.user.userId,
                    currentUserID: currentUserID, safetyAPI: safetyAPI,
                    onAddToList: onAddToList, onBlocked: { onBlocked?() }
                )
            }

            Button(action: onOpenRestaurant) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.restaurant.name).font(.title3.bold()).foregroundStyle(.primary)
                            Text([item.restaurant.city, item.restaurant.address].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        if item.kind == .visit, let visit = item.visit {
                            TasteMapActivityRatingBadge(
                                rating: visit.rating,
                                accessibilityIdentifier: "community-activity-rating-\(visit.id)"
                            )
                        }
                    }
                }
            }.buttonStyle(.plain)

            PublicContentMedia(item: item, photoAPI: photoAPI, onOpenRestaurant: onOpenRestaurant)
            if let note = item.visit?.note {
                Text("“\(note)”").font(.body).foregroundStyle(.primary)
            }

            if let visitID = item.visit?.id, let interactionAPI, let safetyAPI, let currentUserID {
                CommunityInteractionControls(
                    visitID: visitID,
                    initial: item.engagement,
                    currentUserID: currentUserID,
                    authorUserID: item.user.userId,
                    api: interactionAPI,
                    safetyAPI: safetyAPI,
                    onChange: { onEngagementChange?($0) },
                    onBlocked: { onBlocked?() },
                    shareText: shareText
                ) { restaurantActions }
            } else {
                HStack(spacing: 8) {
                    ShareLink(item: shareText) { TasteMapSocialActionLabel(systemImage: "paperplane", count: 0) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("分享动态")
                    Spacer(minLength: 8)
                    restaurantActions
                }
            }
            }
        }
    }

    private var restaurantActions: some View {
        DiscoveryRestaurantQuickActions(
                viewerState: item.viewerState,
                onRecordVisit: onRecordVisit,
                onWantToGo: onWantToGo,
                onAddToList: onAddToList,
                onAddToRoulette: onAddToRoulette,
                identifierPrefix: "community",
                restaurantKey: item.restaurant.globalKey
        )
    }

    private var eventText: String {
        let date = CachedCommunityContent.date(item.eventAt)
        let formatted = date.map(TasteMapDisplayDate.abbreviatedDateTime) ?? item.eventAt
        return item.kind == .visit ? "公开了一次到访 · \(formatted)" : "加入了想吃 · \(formatted)"
    }

    private var shareText: String {
        "\(item.user.displayName) 在 Taste Map 记录了 \(item.restaurant.name)"
    }
}

struct PublicContentMedia: View {
    let item: PublicContentItemV1
    let photoAPI: (any PhotoBinaryAPI)?
    let onOpenRestaurant: () -> Void
    var body: some View {
        PublicContentActivityMedia(presentation: .init(item: item), restaurantName: item.restaurant.name,
                                   tags: item.restaurant.tags, semanticID: item.id, photoAPI: photoAPI,
                                   onOpenRestaurant: onOpenRestaurant)
    }
}

struct PublicContentThumbnail: View {
    let restaurant: PublicContentRestaurantV1
    let photoAPI: (any PhotoBinaryAPI)?

    var body: some View {
        TasteMapRestaurantImage(
            resolution: RestaurantImagePriorityPolicy.resolution(
                localUserPhotoID: nil,
                publicOrCachedPhotoID: restaurant.photo?.photoId,
                providerMerchantImageURL: restaurant.merchantImageUrl
            ),
            photoAPI: photoAPI,
            semanticID: restaurant.globalKey,
            fallbackKind: FoodDiningVisualLibrary.kind(legacySymbol: restaurant.markerEmoji),
            fallbackBackgroundColor: Color.accentColor.opacity(0.14),
            fallbackIconSize: 62,
            categoryVisualID: FoodCategoryVisualResolver.resolve(name: restaurant.name, tags: restaurant.tags),
            accessibilityLabel: "\(restaurant.name)餐厅图片"
        )
    }
}

extension PublicContentItemV1 {
    var discoveryCard: DiscoveryCardV1 {
        .init(
            id: id, mode: .forYou, restaurant: restaurant.discoveryProjection,
            viewerState: viewerState,
            ratings: .init(
                mine: .init(value: nil, sampleCount: 0),
                community: .init(value: visit?.rating, sampleCount: visit?.rating == nil ? 0 : 1),
                friends: .init(value: nil, sampleCount: 0),
                similarTaste: .init(value: nil, sampleCount: 0)
            ),
            reasons: [], sourceUser: nil, similarity: nil, trend: nil,
            cacheScope: cacheScope == .friends ? .friends : .public,
            rank: 0, score: 0
        )
    }
}
