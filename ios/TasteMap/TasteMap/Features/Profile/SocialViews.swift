import SwiftData
import SwiftUI

private enum SocialHubSection: String, CaseIterable, Identifiable {
    case search = "找人"
    case friends = "好友"
    case requests = "请求"
    case follows = "关注"
    var id: Self { self }
}

struct SocialHubView: View {
    @Environment(\.modelContext) private var modelContext
    let currentUserID: String
    let api: any SocialAPI
    @State private var section: SocialHubSection = .search
    @State private var query = ""
    @State private var items: [SocialUserResultV1] = []
    @State private var secondaryItems: [SocialUserResultV1] = []
    @State private var nextCursor: String?
    @State private var selectedUser: SocialUserResultV1?
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("社交关系", selection: $section) {
                    ForEach(SocialHubSection.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()
                Group {
                    if section == .search { searchContent }
                    else { relationshipContent }
                }
            }
            .navigationTitle("好友与关注")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: section) { await loadSection() }
            .sheet(item: $selectedUser) { user in
                SocialPublicProfileView(
                    initial: user, currentUserID: currentUserID, api: api,
                    onChange: { changed in
                        replace(changed)
                        selectedUser = changed
                    }
                )
            }
        }
    }

    private var searchContent: some View {
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
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
            .padding(.bottom, 10)
            if query.count < 2 && items.isEmpty {
                ContentUnavailableView(
                    "找到 Taste Map 用户", systemImage: "person.2.badge.plus",
                    description: Text("输入至少 2 个字符；邮箱和 Apple 登录信息不能用于找人。")
                )
            } else { resultList(emptyTitle: "没有找到这个用户") }
        }
    }

    private var relationshipContent: some View {
        Group {
            if section == .requests {
                List {
                    socialSection("收到的请求", values: items, empty: "还没有收到好友请求")
                    socialSection("已发送", values: secondaryItems, empty: "还没有等待中的请求")
                }
            } else if section == .follows {
                List {
                    socialSection("我关注的", values: items, empty: "还没有关注其他用户")
                    socialSection("关注我的", values: secondaryItems, empty: "还没有人关注你")
                }
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
            ContentUnavailableView(
                emptyTitle, systemImage: "person.2",
                description: Text(message ?? "建立关系后会显示在这里。")
            )
        } else {
            List {
                ForEach(items) { item in row(item) }
                if nextCursor != nil {
                    Button("加载更多") { Task { await loadMore() } }
                        .frame(maxWidth: .infinity)
                }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func socialSection(_ title: String, values: [SocialUserResultV1], empty: String) -> some View {
        Section(title) {
            if values.isEmpty { Text(empty).foregroundStyle(.secondary) }
            else { ForEach(values) { item in row(item) } }
        }
    }

    private func row(_ item: SocialUserResultV1) -> some View {
        Button { selectedUser = item } label: {
            HStack(spacing: 12) {
                PresetProfileAvatarView(preset: item.profile.avatarPresetId)
                    .frame(width: 48, height: 48).clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.profile.displayName).font(.headline).foregroundStyle(.primary)
                    Text([item.profile.city, item.profile.bio].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(item.friendshipState.title).font(.caption).foregroundStyle(.secondary)
                    if item.isFollowing { Text("已关注").font(.caption2).foregroundStyle(Color.accentColor) }
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("social-user-\(item.profile.userId)")
    }

    @MainActor
    private func loadSection() async {
        items = []
        secondaryItems = []
        nextCursor = nil
        message = nil
        guard section != .search else { return }
        loading = true
        defer { loading = false }
        let store = LocalSocialStore(context: modelContext)
        await store.flushQueue(currentUserID: currentUserID, api: api)
        do {
            switch section {
            case .friends:
                let page = try await api.friendships(scope: .friends, cursor: nil, limit: 20)
                try store.cache(page, currentUserID: currentUserID)
                items = page.items; nextCursor = page.nextCursor
            case .requests:
                let incoming = try await api.friendships(scope: .incoming, cursor: nil, limit: 20)
                let outgoing = try await api.friendships(scope: .outgoing, cursor: nil, limit: 20)
                try store.cache(incoming, currentUserID: currentUserID)
                try store.cache(outgoing, currentUserID: currentUserID)
                items = incoming.items; secondaryItems = outgoing.items
            case .follows:
                let following = try await api.follows(scope: .following, cursor: nil, limit: 20)
                let followers = try await api.follows(scope: .followers, cursor: nil, limit: 20)
                try store.cache(following, currentUserID: currentUserID)
                try store.cache(followers, currentUserID: currentUserID)
                items = following.items; secondaryItems = followers.items
            case .search: break
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
        if section == .search { await search(reset: false); return }
        guard section == .friends, let nextCursor else { return }
        do {
            let page = try await api.friendships(scope: .friends, cursor: nextCursor, limit: 20)
            try LocalSocialStore(context: modelContext).cache(page, currentUserID: currentUserID)
            items = deduplicated(items + page.items)
            self.nextCursor = page.nextCursor
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
            items = friendships.filter { $0.perspectiveState == .friends }.compactMap {
                let userID = $0.otherUserID
                return result(userID: userID, state: .friends, following: follows.contains {
                    $0.followerUserID == currentUserID && $0.followedUserID == userID && $0.deletedAt == nil
                })
            }
        case .requests:
            items = friendships.filter { $0.perspectiveState == .incomingRequest }.compactMap { result(userID: $0.otherUserID, state: .incomingRequest) }
            secondaryItems = friendships.filter { $0.perspectiveState == .outgoingRequest }.compactMap { result(userID: $0.otherUserID, state: .outgoingRequest) }
        case .follows:
            items = follows.filter { $0.followerUserID == currentUserID && $0.deletedAt == nil }.compactMap { result(userID: $0.followedUserID, following: true) }
            secondaryItems = follows.filter { $0.followedUserID == currentUserID && $0.deletedAt == nil }.compactMap { result(userID: $0.followerUserID) }
        case .search: break
        }
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
        secondaryItems = secondaryItems.map { $0.id == item.id ? item : $0 }
    }

    private func deduplicated(_ values: [SocialUserResultV1]) -> [SocialUserResultV1] {
        Array(Dictionary(values.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new }).values)
            .sorted { $0.profile.displayName.localizedCompare($1.profile.displayName) == .orderedAscending }
    }
}

struct SocialPublicProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var item: SocialUserResultV1
    @State private var context: SocialProfileContextV1?
    @State private var processing = false
    @State private var message: String?
    let currentUserID: String
    let api: any SocialAPI
    let onChange: (SocialUserResultV1) -> Void

    init(initial: SocialUserResultV1, currentUserID: String, api: any SocialAPI, onChange: @escaping (SocialUserResultV1) -> Void) {
        _item = State(initialValue: initial)
        self.currentUserID = currentUserID
        self.api = api
        self.onChange = onChange
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    PresetProfileAvatarView(preset: item.profile.avatarPresetId)
                        .frame(width: 104, height: 104).clipShape(Circle())
                    Text(item.profile.displayName).font(.title2.bold())
                    if let city = item.profile.city { Label(city, systemImage: "mappin.and.ellipse").foregroundStyle(.secondary) }
                    if let bio = item.profile.bio { Text(bio).multilineTextAlignment(.center).foregroundStyle(.secondary) }
                    HStack(spacing: 12) { friendshipButtons; followButton }
                    if let statistics = context?.profile.statistics {
                        HStack(spacing: 12) {
                            statistic("去过餐厅", statistics.publicRestaurantCount)
                            statistic("可见到访", statistics.publicVisitCount)
                        }
                    }
                    if processing { ProgressView("处理中…") }
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
                .padding(24)
            }
            .navigationTitle("公开主页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { await loadContext() }
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
            Button("解除好友", role: .destructive) { Task { await mutate(.remove) } }.buttonStyle(.bordered)
        }
    }

    private var followButton: some View {
        Button(item.isFollowing ? "已关注" : "关注") { Task { await toggleFollow() } }
            .buttonStyle(.bordered).tint(item.isFollowing ? .secondary : .accentColor)
    }

    private func statistic(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 5) { Text("\(value)").font(.title2.bold()); Text(label).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity).padding().background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    @MainActor
    private func loadContext() async {
        do {
            context = try await api.profileContext(userID: item.profile.userId)
            if let relationship = context?.relationship {
                update(state: relationship.friendshipState, id: relationship.friendshipId, following: relationship.isFollowing)
            }
        } catch { message = "公开资料暂时无法刷新，当前显示缓存。" }
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
        } catch where error is URLError {
            try? LocalSocialStore(context: modelContext).enqueueOptimisticFollow(currentUserID: currentUserID, targetUserID: item.profile.userId, following: next)
            update(state: item.friendshipState, id: item.friendshipId, following: next)
            message = "关注操作已保存在本机，联网后会自动重试。"
        } catch { message = "关注状态没有改变，请稍后重试。" }
    }

    private func update(state: FriendshipPerspectiveState, id: String?, following: Bool) {
        item = .init(profile: item.profile, friendshipId: id, friendshipState: state, isFollowing: following)
        onChange(item)
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
