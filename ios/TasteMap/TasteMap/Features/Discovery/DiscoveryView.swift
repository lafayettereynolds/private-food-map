import SwiftData
import SwiftUI
import UIKit

struct DiscoveryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NativeAuthServices.self) private var authServices
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Environment(PremiumEntitlementService.self) private var premiumEntitlementService
    @Query private var restaurants: [Restaurant]
    @Query private var profiles: [UserProfile]

    @State private var mode: DiscoveryModeV1 = .forYou
    @State private var trendWindowDays = 7
    @State private var authenticatedUser: AuthenticatedUserV1?
    @State private var cards: [DiscoveryCardV1] = []
    @State private var nextCursor: String?
    @State private var loading = false
    @State private var loadingMore = false
    @State private var message: String?
    @State private var cacheDate: Date?
    @State private var showingCache = false
    @State private var selectedCard: DiscoveryCardV1?
    @State private var selectedUser: DiscoveryPublicUserProjectionV1?

    private var city: String {
        if let userID = authenticatedUser?.id,
           let profileCity = profiles.first(where: { $0.tasteMapUserID == userID && $0.deletedAt == nil })?.city,
           !profileCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return profileCity }
        return restaurants.filter { $0.deletedAt == nil && !$0.city.isEmpty }
            .sorted { $0.updatedAt > $1.updatedAt }.first?.city ?? ""
    }

    var body: some View {
        NavigationStack {
            DiscoveryContentView(
                mode: $mode, trendWindowDays: $trendWindowDays,
                cards: cards, loading: loading, message: message,
                cacheDate: cacheDate, showingCache: showingCache,
                isSignedIn: authenticatedUser != nil,
                similarTasteAccess: premiumEntitlementService.access(for: .similarTaste),
                onRetry: { Task { await load(reset: true, preferCache: false) } },
                onOpenRestaurant: { selectedCard = $0 },
                onWantToGo: addToWantToGo,
                onOpenUser: { selectedUser = $0 },
                onLoadMore: { Task { await loadMore() } },
                photoAPI: authServices.photoAPI
            )
            .navigationTitle("发现")
            .background(Color(uiColor: .systemGroupedBackground))
            .refreshable { await load(reset: true, preferCache: false) }
            .task { await restoreAndLoad() }
            .onChange(of: mode) { _, _ in Task { await load(reset: true, preferCache: true) } }
            .onChange(of: premiumEntitlementService.membershipStatus) { _, _ in
                guard mode == .similarTaste else { return }
                Task { await load(reset: true, preferCache: true) }
            }
            .onChange(of: trendWindowDays) { _, _ in
                guard mode == .trending else { return }
                Task { await load(reset: true, preferCache: true) }
            }
            .sheet(item: $selectedCard) { card in
                DiscoveryRestaurantDestination(
                    card: card, restaurants: restaurants,
                    onWantToGo: { addToWantToGo(card) },
                    photoAPI: authServices.photoAPI
                )
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
        if let userID = authenticatedUser?.id {
            await premiumEntitlementService.activate(userID: userID)
        }
        await load(reset: true, preferCache: true)
    }

    @MainActor
    private func load(reset: Bool, preferCache: Bool) async {
        guard let userID = authenticatedUser?.id, !loading else { return }
        if mode == .similarTaste,
           premiumEntitlementService.access(for: .similarTaste) != .allowed {
            cards = []
            nextCursor = nil
            cacheDate = nil
            showingCache = false
            message = nil
            return
        }
#if DEBUG
        if TasteMapUITestFixtures.usesDiscoveryFixture {
            let page = TasteMapUITestFixtures.discoveryPage(mode: mode, window: trendWindowDays)
            cards = page.items
            nextCursor = nil
            cacheDate = .now.addingTimeInterval(-1800)
            showingCache = TasteMapUITestFixtures.usesDiscoveryOfflineFixture
            message = showingCache ? "当前显示上次缓存的内容。" : nil
            return
        }
#endif
        loading = reset
        message = nil
        defer { loading = false }
        let window = mode == .trending ? trendWindowDays : 7
        let store = LocalDiscoveryStore(context: modelContext)
        if reset && preferCache,
           let cached = try? store.cachedPage(mode: mode, city: city, currentUserID: userID,
                                               trendWindowDays: window) {
            cards = cached.cards; cacheDate = cached.updatedAt; showingCache = true
        } else if reset {
            cards = []; nextCursor = nil; showingCache = false
        }
        do {
            let page = try await authServices.discoveryAPI.page(
                mode: mode, city: city, trendWindowDays: window, cursor: nil, limit: 20
            )
            cards = page.items
            nextCursor = page.nextCursor
            cacheDate = LocalDiscoveryStoreDate.parse(page.generatedAt)
            showingCache = false
            try store.replaceCache(page: page, currentUserID: userID, trendWindowDays: window)
            if page.items.isEmpty { message = emptyMessage(page.personalizationConfidence) }
        } catch {
            if cards.isEmpty,
               let cached = try? store.cachedPage(mode: mode, city: city, currentUserID: userID,
                                                   trendWindowDays: window) {
                cards = cached.cards; cacheDate = cached.updatedAt; showingCache = true
            }
            message = cards.isEmpty ? "发现内容暂时无法加载，请检查网络后重试。" : "当前显示上次缓存的内容。"
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
            cards.append(contentsOf: page.items.filter { !existing.contains($0.restaurant.globalKey) })
            nextCursor = page.nextCursor
            try LocalDiscoveryStore(context: modelContext)
                .appendCache(page: page, currentUserID: userID, trendWindowDays: window)
        } catch { message = "加载更多失败，请稍后重试。" }
    }

    @MainActor
    private func addToWantToGo(_ card: DiscoveryCardV1) {
        guard card.viewerState == .none, let userID = authenticatedUser?.id else { return }
        do {
            let store = LocalDiscoveryStore(context: modelContext)
            let restaurant = try store.addToWantToGo(projection: card.restaurant, among: restaurants)
            let state: DiscoveryViewerRestaurantStateV1 = restaurant.status == .visited ? .visited : .wantToGo
            cards = cards.map { value in
                guard value.restaurant.globalKey == card.restaurant.globalKey else { return value }
                var changed = value; changed.viewerState = state; return changed
            }
            try store.updateViewerState(globalKey: card.restaurant.globalKey,
                                        currentUserID: userID, state: state)
            Task { await syncCoordinator.synchronizeNow() }
        } catch { message = "没有成功加入想吃，请稍后重试。" }
    }

    private func emptyMessage(_ confidence: DiscoveryConfidenceV1) -> String {
        if mode == .similarTaste && confidence == .insufficient { return "共同评分数据还不够，多记录几次后再来看看。" }
        return city.isEmpty ? "先在个人资料设置城市，或记录一家餐厅。" : "这个城市暂时还没有可见的真实发现内容。"
    }
}

private enum LocalDiscoveryStoreDate {
    static func parse(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

struct DiscoveryContentView: View {
    @Binding var mode: DiscoveryModeV1
    @Binding var trendWindowDays: Int
    let cards: [DiscoveryCardV1]
    let loading: Bool
    let message: String?
    let cacheDate: Date?
    let showingCache: Bool
    let isSignedIn: Bool
    var similarTasteAccess: PremiumAccessDecision = .allowed
    let onRetry: () -> Void
    let onOpenRestaurant: (DiscoveryCardV1) -> Void
    let onWantToGo: (DiscoveryCardV1) -> Void
    let onOpenUser: (DiscoveryPublicUserProjectionV1) -> Void
    let onLoadMore: () -> Void
    let photoAPI: (any PhotoBinaryAPI)?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Picker("发现内容", selection: $mode) {
                    ForEach(DiscoveryModeV1.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if mode == .trending {
                    Picker("趋势窗口", selection: $trendWindowDays) {
                        Text("近 7 天").tag(7); Text("近 30 天").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
                if showingCache, let cacheDate {
                    Label("离线内容 · 更新于 \(cacheDate.formatted(.relative(presentation: .named)))",
                          systemImage: "wifi.slash")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)

            if !isSignedIn {
                ContentUnavailableView("登录后发现", systemImage: "person.crop.circle.badge.checkmark",
                                       description: Text("请先到“我的”使用 Apple 登录。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if mode == .similarTaste && similarTasteAccess != .allowed {
                if similarTasteAccess == .loading {
                    ProgressView("正在确认同味权益…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    PremiumFeatureLockedView(feature: .similarTaste)
                }
            } else if loading && cards.isEmpty {
                ProgressView("正在寻找真实餐厅…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if cards.isEmpty {
                ContentUnavailableView {
                    Label(mode == .similarTaste ? "数据还不够" : "暂时没有发现内容",
                          systemImage: mode == .similarTaste ? "person.2.wave.2" : "fork.knife.circle")
                } description: { Text(message ?? "换个时间再来看看。") }
                actions: { Button("重试", action: onRetry).buttonStyle(.borderedProminent) }
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
                                onOpenUser: onOpenUser, photoAPI: photoAPI
                            )
                            .onAppear { if card.id == cards.last?.id { onLoadMore() } }
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 120)
                }
            }
        }
    }
}

private struct DiscoveryRestaurantCard: View {
    let card: DiscoveryCardV1
    let onOpen: () -> Void
    let onWantToGo: () -> Void
    let onOpenUser: (DiscoveryPublicUserProjectionV1) -> Void
    let photoAPI: (any PhotoBinaryAPI)?

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 12) {
                    DiscoveryRestaurantImage(restaurant: card.restaurant, photoAPI: photoAPI)
                        .frame(height: 178).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(card.restaurant.name).font(.title3.bold()).foregroundStyle(.primary).lineLimit(2)
                            Text([card.restaurant.city, card.restaurant.address].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Text(card.restaurant.markerEmoji).font(.title2)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("discovery-open-\(card.restaurant.globalKey)")
            if let reason = card.reasons.first {
                Label(reason.text, systemImage: reasonIcon)
                    .font(.subheadline.weight(.medium)).foregroundStyle(Color.accentColor)
            }
            ratingRow
            HStack {
                if let source = card.sourceUser {
                    Button { onOpenUser(source) } label: {
                        HStack(spacing: 7) {
                            PresetProfileAvatarView(preset: source.avatarPresetId)
                                .frame(width: 28, height: 28).clipShape(Circle())
                            Text(source.displayName).font(.caption.weight(.semibold))
                        }
                    }.buttonStyle(.plain)
                }
                Spacer()
                wantButton
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var ratingRow: some View {
        HStack(spacing: 8) {
            rating("社区", card.ratings.community)
            if card.ratings.friends.sampleCount > 0 { rating("好友", card.ratings.friends) }
            if card.ratings.similarTaste.sampleCount > 0 { rating("同味", card.ratings.similarTaste) }
            if let trend = card.trend {
                Text("\(trend.windowDays)天 · \(trend.uniqueVisitorCount)人到访")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func rating(_ label: String, _ rating: DiscoveryRatingProjectionV1) -> some View {
        HStack(spacing: 3) {
            Text(label); Image(systemName: "star.fill").foregroundStyle(.orange)
            Text(rating.value.map { String(format: "%.1f", $0) } ?? "—")
            Text("(\(rating.sampleCount))").foregroundStyle(.tertiary)
        }.font(.caption2)
    }

    @ViewBuilder private var wantButton: some View {
        switch card.viewerState {
        case .none:
            Button(action: onWantToGo) { Label("想吃", systemImage: "bookmark") }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .accessibilityIdentifier("discovery-want-\(card.restaurant.globalKey)")
        case .wantToGo:
            Label("已想吃", systemImage: "bookmark.fill").font(.caption.weight(.semibold)).foregroundStyle(.blue)
        case .visited:
            Label("去过", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(.green)
        }
    }

    private var reasonIcon: String {
        switch card.mode { case .forYou: "sparkles"; case .similarTaste: "person.2.wave.2"; case .trending: "flame.fill" }
    }
}

struct DiscoveryRestaurantImage: View {
    let restaurant: DiscoveryRestaurantProjectionV1
    let photoAPI: (any PhotoBinaryAPI)?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else if let value = restaurant.merchantImageUrl, let url = URL(string: value) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { placeholder }
                }
            } else { placeholder }
        }
        .clipped()
        .task(id: restaurant.photo?.photoId) {
            guard let photo = restaurant.photo, let id = UUID(uuidString: photo.photoId), let photoAPI else { return }
            if let data = try? await photoAPI.download(photoID: id, variant: .thumbnail) { image = UIImage(data: data) }
        }
    }

    private var placeholder: some View {
        LinearGradient(colors: [Color.accentColor.opacity(0.16), .orange.opacity(0.12)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Text(restaurant.markerEmoji).font(.system(size: 56)))
    }
}

struct DiscoveryRestaurantDestination: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    let card: DiscoveryCardV1
    let restaurants: [Restaurant]
    let onWantToGo: () -> Void
    let photoAPI: (any PhotoBinaryAPI)?
    @State private var addingToList = false

    private var currentUserID: String? {
        profiles.first { $0.deletedAt == nil }?.tasteMapUserID
    }

    var body: some View {
        if let local = LocalDiscoveryStore(context: modelContext)
            .localRestaurant(for: card.restaurant, among: restaurants) {
            RestaurantDetailView(restaurant: local)
        } else {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        DiscoveryRestaurantImage(restaurant: card.restaurant, photoAPI: photoAPI)
                            .frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 24))
                        Text(card.restaurant.name).font(.largeTitle.bold())
                        Label([card.restaurant.city, card.restaurant.address].filter { !$0.isEmpty }.joined(separator: " · "),
                              systemImage: "mappin.and.ellipse").foregroundStyle(.secondary)
                        ForEach(card.reasons) { Label($0.text, systemImage: "sparkles").foregroundStyle(Color.accentColor) }
                        Text("这是可浏览的社区餐厅信息。只有你明确加入想吃或记录到访后，才会创建属于你的餐厅记录。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding(18)
                }
                .navigationTitle("餐厅详情").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                    if currentUserID != nil {
                        ToolbarItem(placement: .primaryAction) {
                            Button("加入榜单", systemImage: "list.number") { addingToList = true }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if card.viewerState == .none {
                        Button(action: onWantToGo) { Label("加入想吃", systemImage: "bookmark.fill").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent).controlSize(.large).padding().background(.bar)
                    }
                }
                .sheet(isPresented: $addingToList) {
                    if let currentUserID {
                        AddPlaceToListsSheet(place: card.restaurant, currentUserID: currentUserID)
                    }
                }
            }
        }
    }
}
