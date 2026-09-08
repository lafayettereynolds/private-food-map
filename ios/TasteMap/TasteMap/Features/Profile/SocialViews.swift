import SwiftData
import SwiftUI

enum SocialHubSection: String, CaseIterable, Identifiable {
    case friends = "好友"
    case following = "关注"
    case followers = "粉丝"
    case recommendations = "推荐"
    var id: Self { self }
}

nonisolated enum SocialRelationshipSectionPolicy {
    static func mutualFriends(fromFollowers values: [SocialUserResultV1]) -> [SocialUserResultV1] {
        values.filter(\.isFollowing)
    }
}

private enum SocialRelationshipSectionError: Error {
    case repeatedCursor
    case pageLimitExceeded
}

struct SocialHubView: View {
    @Environment(\.modelContext) private var modelContext
    let currentUserID: String
    let api: any SocialAPI
    let communityAPI: (any CommunityAPI)?
    let collaborationAPI: (any SocialCollaborationAPI)?
    let interactionAPI: (any CommunityInteractionAPI)?
    let safetyAPI: (any ReleaseSafetyAPI)?
    let photoAPI: (any PhotoBinaryAPI)?
    let restaurantListAPI: (any RestaurantListAPI)?
    let navigationTitle: String
    let onClose: (() -> Void)?
    @State private var section: SocialHubSection
    @State private var query = ""
    @State private var items: [SocialUserResultV1] = []
    @State private var nextCursor: String?
    @State private var selectedUser: SocialUserResultV1?
    @State private var loading = false
    @State private var message: String?
    @State private var suggestions: [SocialSuggestionV1]
    @State private var pendingFollowUserIDs: Set<String> = []
    @State private var isShowingCollaborationInbox = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TasteMapSegmentedControl(
                    selection: $section,
                    items: SocialHubSection.allCases.map {
                        .init($0, title: $0.rawValue)
                    },
                    accessibilityIdentifier: "social-hub-section"
                )
                .padding()
                Group {
                    if section == .recommendations { recommendationContent }
                    else { relationshipContent }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .task(id: section) { await loadSection() }
            .sheet(item: $selectedUser) { user in
                SocialPublicProfileView(
                    initial: user, currentUserID: currentUserID, api: api,
                    communityAPI: communityAPI, photoAPI: photoAPI,
                    restaurantListAPI: restaurantListAPI,
                    interactionAPI: interactionAPI,
                    safetyAPI: safetyAPI,
                    onChange: { changed in
                        replace(changed)
                        // The presented profile owns its refreshed data. Keep the
                        // sheet selection stable until the user dismisses it.
                    }
                )
            }
            .sheet(isPresented: $isShowingCollaborationInbox) {
                if let collaborationAPI {
                    SocialCollaborationInboxView(
                        currentUserID: currentUserID,
                        api: collaborationAPI
                    )
                }
            }
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("返回", action: onClose)
                    }
                }
                if collaborationAPI != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isShowingCollaborationInbox = true
                        } label: {
                            Label("协作收件箱", systemImage: "person.2.wave.2")
                        }
                        .accessibilityIdentifier("social-collaboration-inbox")
                    }
                }
            }
        }
    }

    init(
        currentUserID: String,
        api: any SocialAPI,
        communityAPI: (any CommunityAPI)? = nil,
        collaborationAPI: (any SocialCollaborationAPI)? = nil,
        interactionAPI: (any CommunityInteractionAPI)? = nil,
        safetyAPI: (any ReleaseSafetyAPI)? = nil,
        photoAPI: (any PhotoBinaryAPI)? = nil,
        restaurantListAPI: (any RestaurantListAPI)? = nil,
        initialSection: SocialHubSection = .recommendations,
        initialSuggestions: [SocialSuggestionV1] = [],
        navigationTitle: String = "好友与关注",
        onClose: (() -> Void)? = nil
    ) {
        self.currentUserID = currentUserID
        self.api = api
        self.communityAPI = communityAPI
        self.collaborationAPI = collaborationAPI
        self.interactionAPI = interactionAPI
        self.safetyAPI = safetyAPI
        self.photoAPI = photoAPI
        self.restaurantListAPI = restaurantListAPI
        self.navigationTitle = navigationTitle
        self.onClose = onClose
        _section = State(initialValue: initialSection)
        _suggestions = State(initialValue: initialSuggestions)
    }

    private var recommendationContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索显示名称或城市", text: $query)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit { Task { await search(reset: true) } }
                    .accessibilityIdentifier("social-search-field")
                if !query.isEmpty {
                    Button { query = ""; items = []; message = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(TasteMapCoreTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
            .padding(.bottom, 10)
            if query.count < 2 && items.isEmpty {
                if suggestions.isEmpty {
                    TasteMapEmptyState(
                        title: "找到 Taste Map 用户",
                        message: "也可以输入至少 2 个字符搜索用户；邮箱和 Apple 登录信息不能用于搜索。",
                        systemImage: "person.2.badge.plus",
                        presentation: .embedded,
                        accessibilityIdentifier: "social-search-guidance-state"
                    )
                } else {
                    List {
                        Section("推荐给你") {
                            ForEach(suggestions) { suggestion in
                                VStack(alignment: .leading, spacing: 4) {
                                    row(suggestion.user, allowsFollow: true)
                                    if !suggestion.reasons.isEmpty {
                                        Text(suggestion.reasons.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            } else { resultList(emptyTitle: "没有找到这个用户") }
        }
    }

    private var relationshipContent: some View {
        Group {
            if section == .following {
                resultList(emptyTitle: "还没有关注其他用户")
            } else if section == .followers {
                resultList(emptyTitle: "还没有粉丝")
            } else {
                resultList(emptyTitle: "还没有好友")
            }
        }
        .refreshable { await loadSection() }
    }

    @ViewBuilder
    private func resultList(emptyTitle: String) -> some View {
        if loading && items.isEmpty {
            ProgressView("正在加载…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty {
            TasteMapEmptyState(
                title: emptyTitle,
                message: message ?? "建立关系后会显示在这里。",
                systemImage: "person.2",
                presentation: .embedded,
                accessibilityIdentifier: "social-relationship-empty-state"
            )
        } else {
            List {
                ForEach(items) { item in row(item, allowsFollow: section == .recommendations) }
                if nextCursor != nil {
                    Button("加载更多") { Task { await loadMore() } }
                        .frame(maxWidth: .infinity)
                }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
            .listStyle(.plain)
        }
    }

    private func row(_ item: SocialUserResultV1, allowsFollow: Bool = false) -> some View {
        HStack(spacing: 12) {
            Button { selectedUser = item } label: {
                HStack(spacing: 12) {
                    PresetProfileAvatarView(preset: item.profile.avatarPresetId)
                        .frame(width: 48, height: 48).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.profile.displayName).font(.headline).foregroundStyle(.primary)
                        Text(item.profile.city ?? "未设置城市")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("social-user-\(item.profile.userId)")
            if allowsFollow && !item.isFollowing {
                TasteMapCompactFollowButton(
                    userName: item.profile.displayName,
                    isPending: pendingFollowUserIDs.contains(item.id)
                ) {
                    Task { await follow(item) }
                }
                .accessibilityIdentifier("social-follow-\(item.id)")
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(relationshipLabel(for: item)).font(.caption).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func relationshipLabel(for item: SocialUserResultV1) -> String {
        switch section {
        case .friends: "互相关注"
        case .following: "已关注"
        case .followers: item.isFollowing ? "互相关注" : "粉丝"
        case .recommendations: item.isFollowing ? "已关注" : "推荐"
        }
    }

    @MainActor
    private func follow(_ item: SocialUserResultV1) async {
        guard !item.isFollowing, !pendingFollowUserIDs.contains(item.id) else { return }
        pendingFollowUserIDs.insert(item.id)
        defer { pendingFollowUserIDs.remove(item.id) }

        let store = LocalSocialStore(context: modelContext)
        let updated: SocialUserResultV1
        do {
            let response = try await api.setFollowing(true, userID: item.id)
            if let follow = response.follow {
                try store.upsertFollow(follow, currentUserID: currentUserID)
            }
            updated = SocialUserResultV1(
                profile: item.profile,
                friendshipId: item.friendshipId,
                friendshipState: item.friendshipState,
                isFollowing: true
            )
        } catch where error is URLError {
            try? store.enqueueOptimisticFollow(
                currentUserID: currentUserID, targetUserID: item.id, following: true
            )
            updated = SocialUserResultV1(
                profile: item.profile,
                friendshipId: item.friendshipId,
                friendshipState: item.friendshipState,
                isFollowing: true
            )
            message = "关注操作已保存在本机，联网后会自动重试。"
        } catch {
            message = "关注状态没有改变，请稍后重试。"
            return
        }
        replace(updated)
        suggestions = suggestions.map { suggestion in
            suggestion.id == updated.id
                ? SocialSuggestionV1(user: updated, reasons: suggestion.reasons)
                : suggestion
        }
    }

    @MainActor
    private func loadSection() async {
        items = []
        nextCursor = nil
        message = nil
        guard section != .recommendations else {
            if let collaborationAPI {
                if let page = try? await collaborationAPI.suggestions(cursor: nil, limit: 12) {
                    suggestions = page.items
                }
            }
            return
        }
        loading = true
        defer { loading = false }
        let store = LocalSocialStore(context: modelContext)
        await store.flushQueue(currentUserID: currentUserID, api: api)
        do {
            switch section {
            case .friends:
                let page = try await mutualFollowPage(cursor: nil, store: store)
                items = page.items; nextCursor = page.nextCursor
            case .following:
                let following = try await api.follows(scope: .following, cursor: nil, limit: 20)
                try store.cacheFollowPage(
                    following, scope: .following, currentUserID: currentUserID
                )
                items = following.items
                nextCursor = following.nextCursor
            case .followers:
                let followers = try await api.follows(scope: .followers, cursor: nil, limit: 20)
                try store.cacheFollowPage(
                    followers, scope: .followers, currentUserID: currentUserID
                )
                items = followers.items
                nextCursor = followers.nextCursor
            case .recommendations: break
            }
        } catch {
            loadCached(for: section)
            message = items.isEmpty ? "暂时无法连接服务器，请稍后重试。" : "当前显示上次缓存的结果。"
        }
    }

    @MainActor
    private func search(reset: Bool) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { items = []; message = "请输入至少 2 个字符。"; return }
        loading = true
        defer { loading = false }
        if reset { items = []; nextCursor = nil }
        do {
            let page = try await api.search(query: trimmed, cursor: reset ? nil : nextCursor, limit: 20)
            try LocalSocialStore(context: modelContext).cache(page, currentUserID: currentUserID)
            items = reset ? page.items : deduplicated(items + page.items)
            nextCursor = page.nextCursor
            message = page.items.isEmpty && reset ? "换个显示名称或城市试试。" : nil
        } catch {
            let store = LocalSocialStore(context: modelContext)
            let cached = (try? store.cachedProfiles()) ?? []
            items = cached.filter {
                $0.displayName.localizedCaseInsensitiveContains(trimmed) ||
                    ($0.city?.localizedCaseInsensitiveContains(trimmed) ?? false)
            }.map { cachedResult(profile: $0, store: store) }
            message = items.isEmpty ? "搜索失败，请检查网络后重试。" : "网络不可用，显示已有缓存。"
        }
    }

    private func loadMore() async {
        if section == .recommendations { await search(reset: false); return }
        let cursor = nextCursor
        guard let cursor else { return }
        let store = LocalSocialStore(context: modelContext)
        do {
            switch section {
            case .friends:
                let page = try await mutualFollowPage(cursor: cursor, store: store)
                items = deduplicated(items + page.items)
                nextCursor = page.nextCursor
            case .following, .followers:
                let scope: FollowListScope = section == .following ? .following : .followers
                let page = try await api.follows(scope: scope, cursor: cursor, limit: 20)
                let combined = deduplicated(items + page.items)
                if page.nextCursor == nil {
                    try store.cache(page, currentUserID: currentUserID)
                    try store.reconcileFollowResults(
                        combined, scope: scope, currentUserID: currentUserID
                    )
                } else {
                    try store.cacheFollowPage(
                        page, scope: scope, currentUserID: currentUserID
                    )
                }
                items = combined
                nextCursor = page.nextCursor
            case .recommendations: break
            }
        } catch { message = "加载更多失败，请稍后重试。" }
    }

    private func loadCached(for section: SocialHubSection) {
        let store = LocalSocialStore(context: modelContext)
        let profiles = Dictionary(uniqueKeysWithValues: ((try? store.cachedProfiles()) ?? []).map { ($0.tasteMapUserID, $0) })
        let friendships = (try? store.cachedFriendships(currentUserID: currentUserID)) ?? []
        let follows = (try? store.cachedFollows(currentUserID: currentUserID)) ?? []
        func result(userID: String, state: FriendshipPerspectiveState = .none, following: Bool = false) -> SocialUserResultV1? {
            guard let profile = profiles[userID] else { return nil }
            return SocialUserResultV1(
                profile: summary(profile),
                friendshipId: friendships.first { $0.otherUserID == userID && $0.deletedAt == nil }?.relationshipID,
                friendshipState: state, isFollowing: following
            )
        }
        switch section {
        case .friends:
            let followingUserIDs = Set(follows.filter {
                $0.followerUserID == currentUserID && $0.deletedAt == nil
            }.map(\.followedUserID))
            items = follows.filter {
                $0.followedUserID == currentUserID && $0.deletedAt == nil
                    && followingUserIDs.contains($0.followerUserID)
            }.compactMap { result(userID: $0.followerUserID, state: .friends, following: true) }
        case .following:
            items = follows.filter { $0.followerUserID == currentUserID && $0.deletedAt == nil }.compactMap { result(userID: $0.followedUserID, following: true) }
        case .followers:
            items = follows.filter { $0.followedUserID == currentUserID && $0.deletedAt == nil }.compactMap { follow in
                let userID = follow.followerUserID
                return result(userID: userID, following: follows.contains {
                    $0.followerUserID == currentUserID && $0.followedUserID == userID && $0.deletedAt == nil
                })
            }
        case .recommendations: break
        }
    }

    @MainActor
    private func mutualFollowPage(
        cursor initialCursor: String?,
        store: LocalSocialStore
    ) async throws -> SocialPageV1<SocialUserResultV1> {
        var cursor = initialCursor
        var seenCursors = Set<String>()
        var followers: [SocialUserResultV1] = []
        for _ in 0..<100 {
            let page = try await api.follows(scope: .followers, cursor: cursor, limit: 20)
            try store.cacheFollowPage(page, scope: .followers, currentUserID: currentUserID)
            followers = deduplicated(followers + page.items)
            guard let next = page.nextCursor else {
                try store.reconcileFollowResults(
                    followers, scope: .followers, currentUserID: currentUserID
                )
                return .init(
                    apiVersion: page.apiVersion,
                    items: SocialRelationshipSectionPolicy.mutualFriends(fromFollowers: followers),
                    nextCursor: nil
                )
            }
            guard seenCursors.insert(next).inserted else {
                throw SocialRelationshipSectionError.repeatedCursor
            }
            cursor = next
        }
        throw SocialRelationshipSectionError.pageLimitExceeded
    }

    private func cachedResult(profile: CachedSocialProfile, store: LocalSocialStore) -> SocialUserResultV1 {
        let friendships = (try? store.cachedFriendships(currentUserID: currentUserID)) ?? []
        let friendship = friendships.first { $0.otherUserID == profile.tasteMapUserID && $0.deletedAt == nil }
        let following = (try? store.cachedFollows(currentUserID: currentUserID).contains {
            $0.followerUserID == currentUserID && $0.followedUserID == profile.tasteMapUserID && $0.deletedAt == nil
        }) ?? false
        return SocialUserResultV1(
            profile: summary(profile), friendshipId: friendship?.relationshipID,
            friendshipState: friendship?.perspectiveState ?? .none, isFollowing: following
        )
    }

    private func summary(_ profile: CachedSocialProfile) -> SocialUserSummaryV1 {
        .init(userId: profile.tasteMapUserID, displayName: profile.displayName, bio: profile.bio,
              city: profile.city, avatarPhotoId: profile.avatarPhotoID, avatarPresetId: profile.avatarPreset)
    }

    private func replace(_ item: SocialUserResultV1) {
        items = items.map { $0.id == item.id ? item : $0 }
    }

    private func deduplicated(_ values: [SocialUserResultV1]) -> [SocialUserResultV1] {
        Array(Dictionary(values.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new }).values)
            .sorted { $0.profile.displayName.localizedCompare($1.profile.displayName) == .orderedAscending }
    }
}

private enum PublicProfileDestination: String, Identifiable, Hashable {
    case footprints, map
    var id: String { rawValue }
}

struct SocialPublicProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Query private var restaurants: [Restaurant]
    @State private var item: SocialUserResultV1
    @State private var context: SocialProfileContextV1?
    @State private var loadingProfileContext = true
    @State private var processing = false
    @State private var message: String?
    @State private var contentSection: PublicContentSectionV1 = .visits
    @State private var contentItems: [PublicContentItemV1] = []
    @State private var contentStatistics: PublicContentStatisticsV1?
    @State private var loadingStatistics = true
    @State private var statisticsMessage: String?
    @State private var followedByOwner: Bool?
    @State private var loadingFollowDirection = true
    @State private var followDirectionMessage: String?
    @State private var destination: PublicProfileDestination?
    @State private var contentNextCursor: String?
    @State private var loadingContent = false
    @State private var contentLoadRevision = 0
    @State private var contentMessage: String?
    @State private var showingContentCache = false
    @State private var selectedContent: PublicContentItemV1?
    @State private var selectedVisitContent: PublicContentItemV1?
    @State private var selectedListContent: PublicContentItemV1?
    @State private var selectedRouletteRestaurantID: UUID?
    @State private var overview: PublicProfileOverviewV1?
    @State private var loadingOverview = true
    @State private var publicMapItems: [PublicContentItemV1] = []
    @State private var loadingPublicMap = true
    @State private var publicMapMessage: String?
    @State private var publicMapShowingCache = false
    @State private var selectedMapRestaurantID: UUID?
    @State private var publicMapFitRequestID = UUID()
    @State private var publicMapRenderState: RestaurantMapRenderState = .loading
    @State private var reportTarget: CommunityReportTarget?
    @State private var confirmingBlock = false
    let currentUserID: String
    let api: any SocialAPI
    let communityAPI: (any CommunityAPI)?
    let photoAPI: (any PhotoBinaryAPI)?
    let restaurantListAPI: (any RestaurantListAPI)?
    let interactionAPI: (any CommunityInteractionAPI)?
    let safetyAPI: (any ReleaseSafetyAPI)?
    let onChange: (SocialUserResultV1) -> Void

    init(
        initial: SocialUserResultV1,
        currentUserID: String,
        api: any SocialAPI,
        communityAPI: (any CommunityAPI)? = nil,
        photoAPI: (any PhotoBinaryAPI)? = nil,
        restaurantListAPI: (any RestaurantListAPI)? = nil,
        interactionAPI: (any CommunityInteractionAPI)? = nil,
        safetyAPI: (any ReleaseSafetyAPI)? = nil,
        onChange: @escaping (SocialUserResultV1) -> Void
    ) {
        _item = State(initialValue: initial)
        self.currentUserID = currentUserID
        self.api = api
        self.communityAPI = communityAPI
        self.photoAPI = photoAPI
        self.restaurantListAPI = restaurantListAPI
        self.interactionAPI = interactionAPI
        self.safetyAPI = safetyAPI
        self.onChange = onChange
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    publicProfileHero

                    if communityAPI != nil {
                        footprintEntries
                    }

                    if let restaurantListAPI {
                        publicEvidenceHeader(
                            eyebrow: "PUBLIC RESTAURANT LISTS",
                            title: "TA 的食单",
                            detail: "只展示当前权限允许查看的真实食单。"
                        )
                        PublicRestaurantListsSection(
                            ownerUserID: item.profile.userId,
                            currentUserID: currentUserID,
                            api: restaurantListAPI,
                            photoAPI: photoAPI
                        )
                        .accessibilityIdentifier("public-profile-lists-section")
                    }

                    if communityAPI != nil { publicFootprints }
                    if processing { ProgressView("处理中…") }
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .refreshable {
                await loadPage()
                await loadContent(reset: true, preferCache: false)
            }
            .navigationTitle("公开主页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if safetyAPI != nil {
                        Menu {
                            Button("举报用户", systemImage: "exclamationmark.bubble") {
                                reportTarget = CommunityReportTarget(
                                    type: .user,
                                    contentID: item.profile.userId,
                                    authorUserID: item.profile.userId,
                                    title: "\(item.profile.displayName) 的公开主页"
                                )
                            }
                            Button("屏蔽用户", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
                                confirmingBlock = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("用户安全操作")
                        .accessibilityIdentifier("social-profile-safety")
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .task { await loadPage() }
            .task(id: contentSection) { await loadContent(reset: true, preferCache: true) }
            .navigationDestination(item: $destination) { target in
                switch target {
                case .footprints: footprintDestination
                case .map: publicMapDestination
                }
            }
            .onChange(of: selectedMapRestaurantID) { _, restaurantID in
                guard let restaurantID else { return }
                selectedContent = publicMapContent(for: restaurantID)
            }
            .sheet(item: $selectedContent, onDismiss: { selectedMapRestaurantID = nil }) { content in
                DiscoveryRestaurantDestination(
                    card: content.discoveryCard, restaurants: restaurants,
                    onWantToGo: { addToWantToGo(content) },
                    onViewerStateChange: { updateViewerState(globalKey: content.restaurant.globalKey, state: $0) },
                    photoAPI: photoAPI,
                    entrySource: .publicProfile
                )
            }
            .sheet(item: $selectedVisitContent) { content in
                VisitEditorView(
                    candidate: content.restaurant.discoveryProjection.restaurantCandidate,
                    onVisitSaved: { _ in
                        updateViewerState(globalKey: content.restaurant.globalKey, state: .visited)
                        Task { await syncCoordinator.synchronizeNow() }
                    }
                )
            }
            .sheet(item: $selectedListContent) { content in
                AddPlaceToListsSheet(
                    place: content.restaurant.discoveryProjection,
                    currentUserID: currentUserID
                )
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
            .sheet(item: $reportTarget) { target in
                if let safetyAPI { CommunityReportSheet(target: target, api: safetyAPI) }
            }
            .alert("屏蔽这个用户？", isPresented: $confirmingBlock) {
                Button("屏蔽", role: .destructive) { Task { await blockProfileOwner() } }
                Button("取消", role: .cancel) {}
            } message: {
                Text("你们将无法在搜索、主页和社区内容中看到对方。已有好友和关注关系会解除。")
            }
        }
    }

    private var publicProfileHero: some View {
        VStack(alignment: .leading, spacing: 15) {
            publicIdentityHeader
            if item.friendshipState != .friends {
                HStack(spacing: 10) {
                    friendshipButtons
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [TasteMapCoreTheme.surface, TasteMapCoreTheme.brandSoft.opacity(0.54)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay { RoundedRectangle(cornerRadius: 24).stroke(TasteMapCoreTheme.border, lineWidth: 1) }
        .accessibilityElement(children: .contain)
    }

    private func publicEvidenceHeader(
        eyebrow: String,
        title: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(TasteMapCoreTheme.brand)
            Text(title).font(.title3.weight(.bold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var publicIdentityHeader: some View {
        VStack(alignment: .center, spacing: 8) {
            PresetProfileAvatarView(preset: item.profile.avatarPresetId)
                .frame(width: 80, height: 80)
                .clipShape(Circle())
            Text(item.profile.displayName)
                .font(.title3.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text("ID \(TasteMapPublicUserID.numeric(from: item.profile.userId))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ProfileConnectionMetrics(
                    followingCount: overview?.followingCount,
                    followerCount: overview?.followerCount,
                    isLoading: loadingOverview,
                    identifierPrefix: "public-profile"
                )
                followButton
            }
            if let followDirectionMessage {
                Text(followDirectionMessage).font(.caption2).foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { publicProfileMetadata }
                VStack(alignment: .center, spacing: 5) { publicProfileMetadata }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var publicProfileMetadata: some View {
        if let city = item.profile.city {
            Label(city, systemImage: "building.2")
        }
        if let joinedAt = context?.profile.joinedAt,
           let joinedDate = SyncRecordMapper.date(joinedAt) {
            Label(
                "加入于 \(TasteMapDisplayDate.yearMonth(joinedDate))",
                systemImage: "calendar.badge.checkmark"
            )
            .accessibilityIdentifier("public-profile-joined-date")
        } else if loadingProfileContext {
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("正在读取加入时间")
            }
            .accessibilityIdentifier("public-profile-joined-date-loading")
        } else {
            Label("加入时间暂时无法加载", systemImage: "calendar.badge.exclamationmark")
                .accessibilityIdentifier("public-profile-joined-date-unavailable")
        }
    }

    private var footprintEntries: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                footprintEntry(.visited, count: contentStatistics?.visibleRestaurantCount, identifier: "visited") {
                    contentSection = .visits
                    destination = .footprints
                }
                footprintEntry(.wantToGo, count: contentStatistics?.visibleWantToGoCount, identifier: "want") {
                    contentSection = .wantToGo
                    destination = .footprints
                }
                Button { destination = .map } label: {
                    Label("地图", systemImage: "map")
                        .frame(maxWidth: .infinity, minHeight: TasteMapDesignTokens.Control.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("public-profile-map-entry")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(TasteMapCoreTheme.brandDeep)
            if let statisticsMessage {
                HStack {
                    Text(statisticsMessage).font(.caption).foregroundStyle(.secondary)
                    Button("重试") { Task { await loadStatistics() } }.font(.caption)
                }
            }
        }
        .accessibilityIdentifier("public-profile-footprint-entries")
    }

    private func footprintEntry(_ status: RestaurantStatus, count: Int?, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Label(status.title, systemImage: status.systemImage)
                if let count { Text(count, format: .number).monospacedDigit() }
                else if loadingStatistics { ProgressView().controlSize(.mini) }
                else { Image(systemName: "exclamationmark.circle") }
            }
            .frame(maxWidth: .infinity, minHeight: TasteMapDesignTokens.Control.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count.map { "\(status.title) \($0) 家餐厅" } ?? "\(status.title)，数量\(loadingStatistics ? "正在加载" : "暂时无法加载")")
        .accessibilityIdentifier("public-profile-\(identifier)-entry")
    }

    private var publicFootprintScopeItems: [TasteMapSegmentedControl<PublicContentSectionV1>.Item] {
        [
            .init(.visits, title: RestaurantStatus.visited.title, systemImage: RestaurantStatus.visited.systemImage),
            .init(.wantToGo, title: RestaurantStatus.wantToGo.title, systemImage: RestaurantStatus.wantToGo.systemImage)
        ]
    }

    private var footprintDestination: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TasteMapSegmentedControl(
                    selection: $contentSection,
                    items: publicFootprintScopeItems,
                    accessibilityIdentifier: "public-profile-content-section"
                )
                publicContent
            }
            .padding(16)
            .accessibilityIdentifier("public-profile-activity-section")
        }
        .navigationTitle("TA 的味觉足迹")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadContent(reset: true, preferCache: false) }
    }

    private var publicMapDestination: some View {
        GeometryReader { geometry in
            ScrollView {
                publicMapSection(mapHeight: max(238, geometry.size.height - 150))
                    .padding(16)
            }
        }
        .navigationTitle("TA 的美食地图")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPublicMapContent() }
        .refreshable { await loadPublicMapContent() }
    }

    @ViewBuilder
    private func publicMapSection(mapHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            publicEvidenceHeader(
                eyebrow: "PUBLIC TASTE MAP",
                title: "TA 的美食地图",
                detail: "地图只使用当前权限允许查看的真实到访与想吃坐标。"
            )

            if loadingPublicMap && publicMapMarkers.isEmpty {
                ProgressView("正在读取公开地图…")
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else if publicMapMarkers.isEmpty {
                TasteMapEmptyState(
                    title: "TA 暂无可显示的公开地图",
                    message: publicMapMessage ?? "公开记录中还没有带有效坐标的餐厅。",
                    systemImage: "map",
                    presentation: .embedded,
                    accessibilityIdentifier: "public-profile-map-empty-state"
                )
                .frame(minHeight: 170)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ZStack(alignment: .topLeading) {
                        RestaurantMapView(
                            markers: publicMapMarkers,
                            photosByID: [:],
                            photoCoordinator: nil,
                            photoAPI: photoAPI,
                            userAvatarPreset: item.profile.avatarPresetId,
                            userAvatarPhoto: nil,
                            showsUserLocation: false,
                            selectedRestaurantID: $selectedMapRestaurantID,
                            fitRequestID: publicMapFitRequestID,
                            locationRequestID: nil,
                            onRenderStateChange: { publicMapRenderState = $0 },
                            onViewportChange: { _ in }
                        )
                        .frame(height: mapHeight)
                        .accessibilityIdentifier("public-profile-map")

                        if publicMapShowingCache {
                            Label("显示最近缓存", systemImage: "wifi.slash")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(TasteMapCoreTheme.brandDeep)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(.regularMaterial, in: Capsule())
                                .padding(10)
                        }

                        if case let .failed(mapError) = publicMapRenderState {
                            Text(mapError)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(10)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                                .padding(10)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(TasteMapCoreTheme.border, lineWidth: 1)
                    }

                    Text("当前可见 \(publicMapMarkers.count) 家真实餐厅，点标记可查看餐厅。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let publicMapMessage {
                        Text(publicMapMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("public-profile-map-section")
    }

    private var publicMapMarkers: [RestaurantMapMarkerPresentation] {
        let groups = Dictionary(grouping: publicMapItems) { $0.restaurant.globalKey }
        return groups.keys.sorted().compactMap { globalKey in
            guard let values = groups[globalKey],
                  let representative = values.first(where: { $0.kind == .visit }) ?? values.first else {
                return nil
            }
            let restaurant = representative.restaurant
            guard RestaurantMapCoordinatePolicy.isValid(
                latitude: restaurant.latitude,
                longitude: restaurant.longitude
            ) else { return nil }
            let visits = values.filter { $0.kind == .visit }
            let ratings = visits.compactMap(\.visit?.rating).filter(\.isFinite)
            let averageRating = ratings.isEmpty
                ? nil
                : ratings.reduce(0, +) / Double(ratings.count)
            let photo = representative.restaurant.photo
                ?? values.lazy.compactMap(\.restaurant.photo).first
            let merchantImageURL = RestaurantImagePriorityPolicy.safeHTTPSURL(
                restaurant.merchantImageUrl
            )
            return RestaurantMapMarkerPresentation(
                id: stablePublicMapID(globalKey),
                name: restaurant.name,
                latitude: restaurant.latitude,
                longitude: restaurant.longitude,
                status: visits.isEmpty ? .wantToGo : .visited,
                visual: .emoji(FoodCategoryEmojiResolver.resolve(
                    name: restaurant.name,
                    tags: restaurant.tags,
                    preferredEmoji: restaurant.markerEmoji
                )),
                publicPhotoID: photo?.photoId,
                fallbackMerchantImageURL: merchantImageURL,
                allowsRemoteImages: true,
                visitCount: visits.count,
                averageRating: averageRating,
                distanceKilometers: nil
            )
        }
    }

    private func publicMapContent(for restaurantID: UUID) -> PublicContentItemV1? {
        publicMapItems.first { stablePublicMapID($0.restaurant.globalKey) == restaurantID }
    }

    private func stablePublicMapID(_ semanticID: String) -> UUID {
        if let value = UUID(uuidString: semanticID) { return value }
        var left: UInt64 = 0xcbf29ce484222325
        var right: UInt64 = 0x84222325cbf29ce4
        for byte in semanticID.utf8 {
            left = (left ^ UInt64(byte)) &* 0x100000001b3
            right = (right ^ UInt64(byte &+ 31)) &* 0x100000001b3
        }
        let hex = String(format: "%016llx%016llx", left, right)
        let value = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"
        return UUID(uuidString: value)!
    }

    @ViewBuilder
    private var publicContent: some View {
        if loadingContent && contentItems.isEmpty {
            ProgressView("正在加载公开内容…").padding(.vertical, 36)
        } else if contentItems.isEmpty {
            TasteMapEmptyState(
                title: contentSection == .visits ? "TA 还没有公开记录" : "TA 还没有公开想吃",
                message: contentMessage ?? "只有用户主动允许展示的内容才会出现在这里。",
                systemImage: contentSection == .visits ? "fork.knife.circle" : "bookmark",
                foodDiningVisualKind: contentSection == .visits ? .genericDining : nil,
                presentation: .embedded,
                accessibilityIdentifier: "public-profile-content-empty-state"
            )
            .frame(minHeight: 220)
        } else {
            LazyVStack(spacing: 14) {
                if showingContentCache {
                    Label("离线显示最近缓存的公开内容", systemImage: "wifi.slash")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let contentStatistics {
                    Text("当前可见：\(contentStatistics.visibleRestaurantCount) 家餐厅 · \(contentStatistics.visibleVisitCount) 次到访")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(contentItems) { content in
                    PublicContentCard(
                        item: content, photoAPI: photoAPI,
                        onOpenRestaurant: { selectedContent = content },
                        onOpenUser: {}, onWantToGo: { addToWantToGo(content) },
                        onRecordVisit: { selectedVisitContent = content },
                        onAddToList: { selectedListContent = content },
                        onAddToRoulette: { addToRoulette(content) },
                        interactionAPI: interactionAPI,
                        safetyAPI: safetyAPI,
                        currentUserID: currentUserID,
                        onEngagementChange: { updateEngagement(contentID: content.id, engagement: $0) },
                        onBlocked: { blockCompletedLocally() }
                    )
                    .onAppear {
                        if content.id == contentItems.last?.id { Task { await loadMoreContent() } }
                    }
                }
                if loadingContent { ProgressView().padding() }
                if let contentMessage { Text(contentMessage).font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }

    @ViewBuilder
    private var friendshipButtons: some View {
        switch item.friendshipState {
        case .none, .rejected, .removed:
            Button("添加好友") { Task { await requestFriend() } }.buttonStyle(.borderedProminent)
        case .outgoingRequest:
            Button("取消请求") { Task { await mutate(.cancel) } }.buttonStyle(.bordered)
        case .incomingRequest:
            Button("接受") { Task { await mutate(.accept) } }.buttonStyle(.borderedProminent)
            Button("拒绝") { Task { await mutate(.reject) } }.buttonStyle(.bordered)
        case .friends:
            EmptyView()
        }
    }

    private var followButton: some View {
        Button(PublicProfileFollowDirection.label(isFollowing: item.isFollowing, followedByOwner: followedByOwner)) {
            Task { await toggleFollow() }
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.semibold))
        .foregroundStyle(TasteMapCoreTheme.brandDeep)
        .frame(minHeight: TasteMapDesignTokens.Control.minimumHitTarget)
        .disabled(processing)
        .accessibilityHint(loadingFollowDirection ? "正在刷新双方关注关系，仍可操作关注" : "切换对 TA 的关注状态")
        .accessibilityIdentifier("public-profile-follow-action")
    }

    private var publicFootprints: some View {
        VStack(alignment: .leading, spacing: TasteMapDesignTokens.Spacing.regular) {
            publicEvidenceHeader(
                eyebrow: "TASTE FOOTPRINTS",
                title: "TA 的味觉足迹",
                detail: "只展示 TA 允许你查看的真实记录。"
            )
            TasteMapSegmentedControl(
                selection: $contentSection,
                items: publicFootprintScopeItems,
                accessibilityIdentifier: "public-profile-home-content-section"
            )
            publicContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("public-profile-home-footprints")
    }

    @MainActor
    private func loadPage() async {
        guard await loadContext() else { return }
        async let overviewLoad: Void = loadOverview()
        async let statisticsLoad: Void = loadStatistics()
        async let directionLoad: Void = loadFollowDirection()
        _ = await (overviewLoad, statisticsLoad, directionLoad)
    }

    @MainActor
    private func loadStatistics() async {
        guard let communityAPI else { loadingStatistics = false; return }
        loadingStatistics = true
        defer { loadingStatistics = false }
        do {
            #if DEBUG
            if TasteMapUITestFixtures.usesCommunityFixture {
                contentStatistics = TasteMapUITestFixtures.communityPublicContent(userID: item.id, section: .visits).statistics
                return
            }
            #endif
            let page = try await communityAPI.publicContent(userID: item.id, section: .visits, cursor: nil, limit: 1)
            contentStatistics = page.statistics
            statisticsMessage = nil
        } catch {
            contentStatistics = nil
            statisticsMessage = "可见餐厅数量暂时无法加载。"
        }
    }

    @MainActor
    private func loadFollowDirection() async {
        loadingFollowDirection = true
        defer { loadingFollowDirection = false }
        do {
            followedByOwner = try await PublicProfileFollowDirection.load(ownerUserID: item.id, api: api)
            followDirectionMessage = nil
        } catch {
            followedByOwner = nil
            followDirectionMessage = "对方关注状态暂时无法刷新。"
        }
    }

    @MainActor
    private func loadContext() async -> Bool {
        loadingProfileContext = true
        defer { loadingProfileContext = false }
        do {
            #if DEBUG
            context = TasteMapUITestFixtures.usesCommunityFixture
                ? TasteMapUITestFixtures.communityPublicProfileContext(userID: item.profile.userId)
                : try await api.profileContext(userID: item.profile.userId)
            #else
            context = try await api.profileContext(userID: item.profile.userId)
            #endif
            if let relationship = context?.relationship {
                let profile = context!.profile
                let refreshed = SocialUserResultV1(
                    profile: .init(
                        userId: profile.userId, displayName: profile.displayName,
                        bio: profile.bio, city: profile.city,
                        avatarPhotoId: profile.avatarPhotoId,
                        avatarPresetId: profile.avatarPresetId
                    ),
                    friendshipId: relationship.friendshipId,
                    friendshipState: relationship.friendshipState,
                    isFollowing: relationship.isFollowing
                )
                try LocalSocialStore(context: modelContext).cache(
                    refreshed, currentUserID: currentUserID
                )
                let relationshipChanged = refreshed != item
                item = refreshed
                if relationshipChanged { onChange(refreshed) }
            }
            return true
        } catch SyncAPIError.server(let status, _) where status == 403 || status == 404 {
            contentLoadRevision += 1
            contentItems.removeAll()
            publicMapItems.removeAll()
            try? LocalCommunityStore(context: modelContext)
                .invalidateOwner(item.profile.userId, currentUserID: currentUserID)
            try? LocalSocialStore(context: modelContext).invalidateProfile(item.profile.userId)
            dismiss()
            return false
        } catch {
            message = "公开资料暂时无法刷新；其他公开内容仍会继续加载。"
            return true
        }
    }

    @MainActor
    private func loadOverview() async {
        guard let communityAPI else {
            loadingOverview = false
            return
        }
        loadingOverview = true
        defer { loadingOverview = false }
        do {
            #if DEBUG
            if TasteMapUITestFixtures.usesCommunityFixture {
                overview = TasteMapUITestFixtures.communityPublicOverview(userID: item.profile.userId)
                return
            }
            #endif
            overview = try await communityAPI.publicOverview(userID: item.profile.userId)
        } catch {
            overview = nil
        }
    }

    @MainActor
    private func loadPublicMapContent() async {
        guard let communityAPI else {
            loadingPublicMap = false
            return
        }
        let cachedItems = cachedPublicMapItems()
        if !cachedItems.isEmpty {
            publicMapItems = cachedItems
            publicMapShowingCache = true
        }
        loadingPublicMap = true
        defer { loadingPublicMap = false }

        var resolvedItems: [PublicContentItemV1] = []
        var failedSectionCount = 0
        for section in [PublicContentSectionV1.visits, .wantToGo] {
            do {
                let values = try await fetchAllPublicContent(
                    api: communityAPI,
                    section: section,
                    maximumItemCount: 300
                )
                resolvedItems.append(contentsOf: values)
                try LocalCommunityStore(context: modelContext).replace(
                    items: values,
                    currentUserID: currentUserID,
                    routeKey: LocalCommunityStore.profileRoute(
                        userID: item.profile.userId,
                        section: section
                    ),
                    fetchedAt: .now
                )
            } catch {
                failedSectionCount += 1
                if let cached = try? LocalCommunityStore(context: modelContext).cached(
                    currentUserID: currentUserID,
                    routeKey: LocalCommunityStore.profileRoute(
                        userID: item.profile.userId,
                        section: section
                    )
                ) {
                    resolvedItems.append(contentsOf: cached.items)
                }
            }
        }

        let uniqueItems = deduplicatedPublicContent(resolvedItems)
        if !uniqueItems.isEmpty || failedSectionCount < 2 {
            publicMapItems = uniqueItems
            publicMapFitRequestID = UUID()
        }
        publicMapShowingCache = failedSectionCount > 0 && !publicMapItems.isEmpty
        switch (failedSectionCount, publicMapItems.isEmpty) {
        case (2, true):
            publicMapMessage = "公开地图暂时无法加载，请稍后重试。"
        case (1..., false):
            publicMapMessage = "部分公开记录刷新失败，当前地图同时包含最近缓存。"
        default:
            publicMapMessage = nil
        }
    }

    @MainActor
    private func fetchAllPublicContent(
        api: any CommunityAPI,
        section: PublicContentSectionV1,
        maximumItemCount: Int
    ) async throws -> [PublicContentItemV1] {
        var result: [PublicContentItemV1] = []
        var cursor: String?
        var seenCursors = Set<String>()
        var pageCount = 0
        repeat {
            #if DEBUG
            if TasteMapUITestFixtures.usesCommunityFixture {
                return TasteMapUITestFixtures.communityPublicContent(
                    userID: item.profile.userId,
                    section: section
                ).items
            }
            #endif
            pageCount += 1
            let page = try await api.publicContent(
                userID: item.profile.userId,
                section: section,
                cursor: cursor,
                limit: min(50, maximumItemCount - result.count)
            )
            var seenItems = Set(result.map(\.id))
            result.append(contentsOf: page.items.filter { seenItems.insert($0.id).inserted })
            guard result.count < maximumItemCount,
                  pageCount < 20,
                  let nextCursor = page.nextCursor,
                  seenCursors.insert(nextCursor).inserted else {
                cursor = nil
                continue
            }
            cursor = nextCursor
        } while cursor != nil
        return result
    }

    @MainActor
    private func cachedPublicMapItems() -> [PublicContentItemV1] {
        let store = LocalCommunityStore(context: modelContext)
        return deduplicatedPublicContent(
            [PublicContentSectionV1.visits, .wantToGo].flatMap { section in
                (try? store.cached(
                    currentUserID: currentUserID,
                    routeKey: LocalCommunityStore.profileRoute(
                        userID: item.profile.userId,
                        section: section
                    )
                )?.items) ?? []
            }
        )
    }

    private func deduplicatedPublicContent(
        _ values: [PublicContentItemV1]
    ) -> [PublicContentItemV1] {
        var seen = Set<String>()
        return values
            .sorted { $0.eventAt > $1.eventAt }
            .filter { seen.insert($0.id).inserted }
    }

    @MainActor
    private func requestFriend() async {
        processing = true; defer { processing = false }
        do {
            let response = try await api.requestFriend(userID: item.profile.userId)
            try LocalSocialStore(context: modelContext).upsertFriendship(response.friendship, currentUserID: currentUserID)
            update(state: response.friendship.state == .friends ? .friends : .outgoingRequest, id: response.friendship.id, following: item.isFollowing)
        } catch where error is URLError {
            _ = try? LocalSocialStore(context: modelContext).enqueueOptimisticFriendRequest(currentUserID: currentUserID, targetUserID: item.profile.userId)
            update(state: .outgoingRequest, id: nil, following: item.isFollowing)
            message = "请求已保存在本机，联网后会自动重试。"
        } catch { message = "好友请求未发送：\(error.localizedDescription)" }
    }

    @MainActor
    private func mutate(_ action: FriendshipMutationAction) async {
        guard let id = item.friendshipId else { message = "请联网刷新关系后再操作。"; return }
        processing = true; defer { processing = false }
        do {
            let response = try await api.mutateFriendship(id: id, action: action)
            try LocalSocialStore(context: modelContext).upsertFriendship(response.friendship, currentUserID: currentUserID)
            let next: FriendshipPerspectiveState = action == .accept ? .friends : .none
            update(state: next, id: next == .none ? nil : id, following: item.isFollowing)
            if next != .friends {
                contentItems.removeAll { $0.cacheScope == .friends }
                try? LocalCommunityStore(context: modelContext)
                    .invalidateOwner(item.profile.userId, currentUserID: currentUserID)
                LocalRestaurantListStore(context: modelContext)
                    .invalidate(ownerUserID: item.profile.userId, viewerUserID: currentUserID)
            }
            _ = await loadContext()
        } catch { message = "关系已变化，请刷新后重试。" }
    }

    @MainActor
    private func toggleFollow() async {
        let next = !item.isFollowing
        processing = true; defer { processing = false }
        do {
            let response = try await api.setFollowing(next, userID: item.profile.userId)
            if let follow = response.follow { try LocalSocialStore(context: modelContext).upsertFollow(follow, currentUserID: currentUserID) }
            update(state: item.friendshipState, id: item.friendshipId, following: next)
            if !next {
                try? LocalCommunityStore(context: modelContext)
                    .invalidateOwner(item.profile.userId, currentUserID: currentUserID)
            }
        } catch where error is URLError {
            try? LocalSocialStore(context: modelContext).enqueueOptimisticFollow(currentUserID: currentUserID, targetUserID: item.profile.userId, following: next)
            update(state: item.friendshipState, id: item.friendshipId, following: next)
            if !next {
                try? LocalCommunityStore(context: modelContext)
                    .invalidateOwner(item.profile.userId, currentUserID: currentUserID)
            }
            message = "关注操作已保存在本机，联网后会自动重试。"
        } catch { message = "关注状态没有改变，请稍后重试。" }
    }

    private func update(state: FriendshipPerspectiveState, id: String?, following: Bool) {
        item = .init(profile: item.profile, friendshipId: id, friendshipState: state, isFollowing: following)
        onChange(item)
    }

    @MainActor
    private func blockProfileOwner() async {
        guard let safetyAPI else { return }
        processing = true
        defer { processing = false }
        do {
            _ = try await safetyAPI.setBlocked(true, userID: item.profile.userId)
            blockCompletedLocally()
        } catch {
            message = "屏蔽没有完成，请稍后重试。"
        }
    }

    @MainActor
    private func blockCompletedLocally() {
        contentItems.removeAll()
        publicMapItems.removeAll()
        try? LocalCommunityStore(context: modelContext)
            .invalidateOwner(item.profile.userId, currentUserID: currentUserID)
        try? LocalSocialStore(context: modelContext).invalidateProfile(item.profile.userId)
        dismiss()
    }

    @MainActor
    private func loadContent(reset: Bool, preferCache: Bool) async {
        guard let communityAPI else { return }
        let section = contentSection
        contentLoadRevision += 1
        let revision = contentLoadRevision
        let route = LocalCommunityStore.profileRoute(userID: item.profile.userId, section: section)
        if reset {
            contentItems = []
            contentNextCursor = nil
            contentMessage = nil
            showingContentCache = false
        }
        if reset && preferCache, let cached = try? LocalCommunityStore(context: modelContext)
            .cached(currentUserID: currentUserID, routeKey: route) {
            contentItems = cached.items
            showingContentCache = true
        }
        loadingContent = true
        defer { if revision == contentLoadRevision { loadingContent = false } }
        do {
            #if DEBUG
            let page = TasteMapUITestFixtures.usesCommunityFixture
                ? TasteMapUITestFixtures.communityPublicContent(
                    userID: item.profile.userId,
                    section: section
                )
                : try await communityAPI.publicContent(
                    userID: item.profile.userId, section: section, cursor: nil, limit: 20
                )
            #else
            let page = try await communityAPI.publicContent(
                userID: item.profile.userId, section: section, cursor: nil, limit: 20
            )
            #endif
            guard !Task.isCancelled, revision == contentLoadRevision, section == contentSection else { return }
            contentItems = page.items
            contentStatistics = page.statistics
            contentNextCursor = page.nextCursor
            contentMessage = nil
            showingContentCache = false
            try LocalCommunityStore(context: modelContext).replace(
                items: page.items, currentUserID: currentUserID, routeKey: route,
                fetchedAt: CachedCommunityContent.date(page.generatedAt) ?? .now
            )
        } catch SyncAPIError.server(let status, _) where status == 403 || status == 404 {
            guard revision == contentLoadRevision, section == contentSection else { return }
            contentItems = []
            contentNextCursor = nil
            contentStatistics = nil
            showingContentCache = false
            contentMessage = "这些记录已不再允许查看。"
            try? LocalCommunityStore(context: modelContext).invalidateOwner(item.id, currentUserID: currentUserID)
        } catch {
            guard !Task.isCancelled, revision == contentLoadRevision, section == contentSection else { return }
            if contentItems.isEmpty, let cached = try? LocalCommunityStore(context: modelContext)
                .cached(currentUserID: currentUserID, routeKey: route) {
                contentItems = cached.items; showingContentCache = true
            }
            contentMessage = contentItems.isEmpty ? "公开内容暂时无法加载。" : "刷新失败，继续显示已有缓存。"
        }
    }

    @MainActor
    private func loadMoreContent() async {
        guard let communityAPI, let cursor = contentNextCursor, !loadingContent else { return }
        let section = contentSection
        let revision = contentLoadRevision
        loadingContent = true
        defer { if revision == contentLoadRevision { loadingContent = false } }
        do {
            let page = try await communityAPI.publicContent(
                userID: item.profile.userId, section: section, cursor: cursor, limit: 20
            )
            guard !Task.isCancelled, revision == contentLoadRevision, section == contentSection else { return }
            var seen = Set(contentItems.map(\.id))
            contentItems.append(contentsOf: page.items.filter { seen.insert($0.id).inserted })
            contentNextCursor = page.nextCursor
            try LocalCommunityStore(context: modelContext).append(
                items: page.items, currentUserID: currentUserID,
                routeKey: LocalCommunityStore.profileRoute(userID: item.profile.userId, section: section),
                fetchedAt: CachedCommunityContent.date(page.generatedAt) ?? .now
            )
        } catch {
            guard !Task.isCancelled, revision == contentLoadRevision, section == contentSection else { return }
            contentMessage = "加载更多失败，请稍后重试。"
        }
    }

    @MainActor
    private func addToWantToGo(_ content: PublicContentItemV1) {
        guard content.viewerState == .none else { return }
        do {
            let restaurant = try LocalDiscoveryStore(context: modelContext).addToWantToGo(
                projection: content.restaurant.discoveryProjection,
                among: ownedRestaurants,
                currentUserID: currentUserID
            )
            updateViewerState(
                globalKey: content.restaurant.globalKey,
                state: restaurant.status == .visited ? .visited : .wantToGo
            )
            Task { await syncCoordinator.synchronizeNow() }
        } catch { contentMessage = "暂时无法加入想吃，请稍后重试。" }
    }

    private var ownedRestaurants: [Restaurant] {
        restaurants.filter { $0.ownerUserID == currentUserID && $0.deletedAt == nil }
    }

    @MainActor
    private func addToRoulette(_ content: PublicContentItemV1) {
        do {
            let restaurant = try LocalDiscoveryStore(context: modelContext).addToWantToGo(
                projection: content.restaurant.discoveryProjection,
                among: ownedRestaurants,
                currentUserID: currentUserID
            )
            updateViewerState(
                globalKey: content.restaurant.globalKey,
                state: restaurant.status == .visited ? .visited : .wantToGo
            )
            selectedRouletteRestaurantID = restaurant.id
            Task { await syncCoordinator.synchronizeNow() }
        } catch { contentMessage = "暂时无法加入轮盘，请稍后重试。" }
    }

    @MainActor
    private func updateViewerState(globalKey: String, state: DiscoveryViewerRestaurantStateV1) {
        // This is the viewer's status, never a mutation of the author's Visit.
        for index in contentItems.indices where contentItems[index].restaurant.globalKey == globalKey {
            contentItems[index].viewerState = state
        }
        try? LocalCommunityStore(context: modelContext).updateViewerState(
            globalKey: globalKey, currentUserID: currentUserID, state: state
        )
    }

    private func updateEngagement(contentID: String, engagement: CommunityEngagementSummaryV1) {
        guard let index = contentItems.firstIndex(where: { $0.id == contentID }) else { return }
        contentItems[index].engagement = engagement
    }
}

#if DEBUG
private let previewUsers: [SocialUserResultV1] = [
    .init(profile: .init(userId: "tm_preview_a", displayName: "杭州拉面观察员", bio: "喜欢热汤面和深夜食堂", city: "杭州", avatarPhotoId: nil, avatarPresetId: .otter), friendshipId: nil, friendshipState: .none, isFollowing: false),
    .init(profile: .init(userId: "tm_preview_b", displayName: "一个非常非常长的 Taste Map 用户名字", bio: "这是一段用于验证大字体、长文字和多行布局的个人简介。", city: "上海", avatarPhotoId: nil, avatarPresetId: .panda), friendshipId: "friendship:a:b", friendshipState: .friends, isFollowing: true),
]

@MainActor
private final class PreviewSocialAPI: SocialAPI {
    let users: [SocialUserResultV1]
    init(users: [SocialUserResultV1]) { self.users = users }
    func search(query: String, cursor: String?, limit: Int) async throws -> SocialPageV1<SocialUserResultV1> { .init(apiVersion: 1, items: users, nextCursor: nil) }
    func friendships(scope: FriendshipListScope, cursor: String?, limit: Int) async throws -> SocialPageV1<SocialUserResultV1> { .init(apiVersion: 1, items: users.filter { $0.friendshipState == (scope == .friends ? .friends : scope == .incoming ? .incomingRequest : .outgoingRequest) }, nextCursor: nil) }
    func follows(scope: FollowListScope, cursor: String?, limit: Int) async throws -> SocialPageV1<SocialUserResultV1> { .init(apiVersion: 1, items: users.filter(\.isFollowing), nextCursor: nil) }
    func profileContext(userID: String) async throws -> SocialProfileContextV1 {
        let item = users.first { $0.id == userID } ?? users[0]
        return .init(apiVersion: 1, profile: .init(apiVersion: 1, userId: item.profile.userId, displayName: item.profile.displayName, bio: item.profile.bio, city: item.profile.city, avatarPhotoId: nil, avatarPresetId: item.profile.avatarPresetId, joinedAt: "2026-08-28T00:00:00.000Z", statistics: .init(publicRestaurantCount: 12, publicVisitCount: 24)), relationship: .init(friendshipId: item.friendshipId, friendshipState: item.friendshipState, isFollowing: item.isFollowing))
    }
    func requestFriend(userID: String) async throws -> FriendshipMutationResponseV1 { mutation(userID, .outgoingRequest) }
    func mutateFriendship(id: String, action: FriendshipMutationAction) async throws -> FriendshipMutationResponseV1 { mutation("tm_preview_a", action == .accept ? .friends : .removed) }
    func setFollowing(_ following: Bool, userID: String) async throws -> FollowMutationResponseV1 { .init(follow: nil, duplicate: false) }
    private func mutation(_ userID: String, _ state: FriendshipPerspectiveState) -> FriendshipMutationResponseV1 { .init(friendship: .init(apiVersion: 1, id: "friendship:preview", requesterUserId: "tm_me", addresseeUserId: userID, state: state, createdAt: "2026-08-28T00:00:00.000Z", updatedAt: "2026-08-28T00:00:00.000Z", deletedAt: state == .removed ? "2026-08-28T00:00:00.000Z" : nil, serverVersion: 1), duplicate: false, crossRequestAccepted: nil) }
}

#Preview("01 搜索初始") { SocialHubView(currentUserID: "tm_me", api: PreviewSocialAPI(users: previewUsers)).modelContainer(for: [CachedSocialProfile.self, CachedFriendship.self, CachedFollow.self, SocialMutation.self], inMemory: true) }
#Preview("02 搜索结果") { SocialHubView(currentUserID: "tm_me", api: PreviewSocialAPI(users: previewUsers)).modelContainer(for: [CachedSocialProfile.self, CachedFriendship.self, CachedFollow.self, SocialMutation.self], inMemory: true) }
#Preview("03 无结果") { SocialHubView(currentUserID: "tm_me", api: PreviewSocialAPI(users: [])).modelContainer(for: [CachedSocialProfile.self, CachedFriendship.self, CachedFollow.self, SocialMutation.self], inMemory: true) }
#Preview("04 无关系") { SocialPublicProfileView(initial: previewUsers[0], currentUserID: "tm_me", api: PreviewSocialAPI(users: previewUsers), onChange: { _ in }).modelContainer(for: [CachedSocialProfile.self, CachedFriendship.self, CachedFollow.self, SocialMutation.self], inMemory: true) }
#Preview("05 已发送") { SocialPublicProfileView(initial: .init(profile: previewUsers[0].profile, friendshipId: "f", friendshipState: .outgoingRequest, isFollowing: false), currentUserID: "tm_me", api: PreviewSocialAPI(users: previewUsers), onChange: { _ in }).modelContainer(for: [CachedSocialProfile.self, CachedFriendship.self, CachedFollow.self, SocialMutation.self], inMemory: true) }
#Preview("06 收到请求") { SocialPublicProfileView(initial: .init(profile: previewUsers[0].profile, friendshipId: "f", friendshipState: .incomingRequest, isFollowing: false), currentUserID: "tm_me", api: PreviewSocialAPI(users: previewUsers), onChange: { _ in }).modelContainer(for: [CachedSocialProfile.self, CachedFriendship.self, CachedFollow.self, SocialMutation.self], inMemory: true) }
#Preview("07 已是好友") { SocialPublicProfileView(initial: previewUsers[1], currentUserID: "tm_me", api: PreviewSocialAPI(users: previewUsers), onChange: { _ in }).modelContainer(for: [CachedSocialProfile.self, CachedFriendship.self, CachedFollow.self, SocialMutation.self], inMemory: true) }
#Preview("08 好友列表为空") { SocialHubView(currentUserID: "tm_me", api: PreviewSocialAPI(users: [])).modelContainer(for: [CachedSocialProfile.self, CachedFriendship.self, CachedFollow.self, SocialMutation.self], inMemory: true) }
#Preview("09 好友列表多人") { SocialHubView(currentUserID: "tm_me", api: PreviewSocialAPI(users: previewUsers)).modelContainer(for: [CachedSocialProfile.self, CachedFriendship.self, CachedFollow.self, SocialMutation.self], inMemory: true) }
#Preview("10 多个请求") { SocialHubView(currentUserID: "tm_me", api: PreviewSocialAPI(users: previewUsers)).modelContainer(for: [CachedSocialProfile.self, CachedFriendship.self, CachedFollow.self, SocialMutation.self], inMemory: true) }
#Preview("11 非好友公开主页") { SocialPublicProfileView(initial: previewUsers[0], currentUserID: "tm_me", api: PreviewSocialAPI(users: previewUsers), onChange: { _ in }).modelContainer(for: [CachedSocialProfile.self, CachedFriendship.self, CachedFollow.self, SocialMutation.self], inMemory: true) }
#Preview("12 好友公开主页") { SocialPublicProfileView(initial: previewUsers[1], currentUserID: "tm_me", api: PreviewSocialAPI(users: previewUsers), onChange: { _ in }).modelContainer(for: [CachedSocialProfile.self, CachedFriendship.self, CachedFollow.self, SocialMutation.self], inMemory: true) }
#Preview("13 关注状态") { SocialPublicProfileView(initial: .init(profile: previewUsers[0].profile, friendshipId: nil, friendshipState: .none, isFollowing: true), currentUserID: "tm_me", api: PreviewSocialAPI(users: previewUsers), onChange: { _ in }).modelContainer(for: [CachedSocialProfile.self, CachedFriendship.self, CachedFollow.self, SocialMutation.self], inMemory: true) }
#Preview("14 长名字简介") { SocialPublicProfileView(initial: previewUsers[1], currentUserID: "tm_me", api: PreviewSocialAPI(users: previewUsers), onChange: { _ in }).modelContainer(for: [CachedSocialProfile.self, CachedFriendship.self, CachedFollow.self, SocialMutation.self], inMemory: true) }
#Preview("15 小屏") { SocialHubView(currentUserID: "tm_me", api: PreviewSocialAPI(users: previewUsers)).modelContainer(for: [CachedSocialProfile.self, CachedFriendship.self, CachedFollow.self, SocialMutation.self], inMemory: true).frame(width: 320, height: 568) }
#Preview("16 大字体") { SocialPublicProfileView(initial: previewUsers[1], currentUserID: "tm_me", api: PreviewSocialAPI(users: previewUsers), onChange: { _ in }).modelContainer(for: [CachedSocialProfile.self, CachedFriendship.self, CachedFollow.self, SocialMutation.self], inMemory: true).environment(\.dynamicTypeSize, .accessibility3) }
#endif
