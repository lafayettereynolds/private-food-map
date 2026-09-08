import AuthenticationServices
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

private enum ProfileBrowseDestination: Hashable {
    case visited
    case wantToGo
    case footprints
}

struct ProfileView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @Environment(\.photoTransferCoordinator) private var photoTransferCoordinator
    @Environment(NativeAuthServices.self) private var authServices
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Environment(PremiumEntitlementService.self) private var premiumEntitlementService
    @Query private var restaurants: [Restaurant]
    @Query private var visits: [Visit]
    @Query private var profiles: [UserProfile]
    @Query private var photos: [PhotoAsset]
    @Query private var restaurantLists: [RestaurantList]
    @State private var authenticatedUser: AuthenticatedUserV1?
    @State private var isRunningAuthOperation = false
    @State private var authMessage: String?
    @State private var isEditingProfile = false
    @State private var browseDestination: ProfileBrowseDestination?
    @State private var socialHubSection: SocialHubSection?
    @State private var isShowingSettings = false
    @State private var socialStatistics = ProfileSocialStatistics.zero

    private var ownedContent: ProfileOwnedContentScope.Snapshot {
        ProfileOwnedContentScope.capture(
            currentUserID: authenticatedUser?.id,
            restaurants: restaurants,
            visits: visits,
            photos: photos
        )
    }
    private var activeRestaurants: [Restaurant] { ownedContent.restaurants.filter { $0.deletedAt == nil } }
    private var activeVisits: [Visit] { ownedContent.visits.filter { $0.deletedAt == nil } }
    private var activeListCount: Int {
        guard let userID = authenticatedUser?.id else { return 0 }
        return restaurantLists.filter { $0.ownerUserID == userID && $0.deletedAt == nil }.count
    }
    private var activeProfile: UserProfile? {
        guard let userID = authenticatedUser?.id else { return nil }
        return profiles.first { $0.tasteMapUserID == userID && $0.deletedAt == nil }
    }
    private var avatarPhoto: PhotoAsset? {
        guard let photoID = activeProfile?.avatarPhotoID else { return nil }
        return photos.first {
            ($0.remoteID ?? $0.id.uuidString.lowercased()) == photoID && $0.deletedAt == nil
        }
    }
    private var statistics: ProfileBasicStatistics {
        ProfileBasicStatistics(restaurants: activeRestaurants, visits: activeVisits)
    }
    private var tasteFootprintCount: Int {
        activeVisits.count + RestaurantVisitStatePolicy.partition(
            restaurants: activeRestaurants,
            visits: activeVisits
        ).wantToGo.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ProfileSummaryTemplate(showsStatistics: authenticatedUser != nil) {
                        ProfileIdentityCard(
                            profile: activeProfile,
                            avatarPhoto: avatarPhoto,
                            isSignedIn: authenticatedUser != nil,
                            shareEntityID: activeProfile?.visibility == .public ? authenticatedUser?.id : nil,
                            membershipStatus: premiumEntitlementService.membershipStatus,
                            socialStatistics: socialStatistics,
                            onEdit: { isEditingProfile = true },
                            onSignIn: { Task { await signIn() } },
                            onPremium: { premiumEntitlementService.openPaywall(from: .profile) },
                            onFollowing: { socialHubSection = .following },
                            onFollowers: { socialHubSection = .followers },
                            onDiscover: { socialHubSection = .recommendations },
                            onSettings: { isShowingSettings = true }
                        )
                        if isRunningAuthOperation {
                            ProgressView()
                                .accessibilityLabel("正在处理账户操作")
                        }
                        if let authMessage {
                            Text(authMessage)
                                .font(.footnote)
                                .foregroundStyle(authMessage.hasPrefix("失败") ? .red : .secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } statistics: {
                        ProfileStatisticsSection(
                            statistics: statistics,
                            onVisited: { browseDestination = .visited },
                            onWantToGo: { browseDestination = .wantToGo }
                        )
                    } actions: {
                        primaryActions
                    }
                    if authenticatedUser != nil {
                        memoriesSection
                        listsSection
                        insightsSection
                        tasteFootprintsSection
                    }
                    if authenticatedUser != nil, activeRestaurants.isEmpty {
                        TasteMapEmptyState(
                            title: "还没有美食记录",
                            message: "保存第一次到访后，你的真实记录会显示在这里。",
                            systemImage: "fork.knife.circle",
                            foodDiningVisualKind: .genericDining,
                            presentation: .embedded,
                            accessibilityIdentifier: "profile-records-empty-state"
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    settingsEntry
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 110)
            }
            .background(TasteMapCoreTheme.page)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $browseDestination) { destination in
                switch destination {
                case .visited:
                    RestaurantCollectionView(segment: .visited, currentUserID: authenticatedUser?.id)
                case .wantToGo:
                    RestaurantCollectionView(segment: .wantToGo, currentUserID: authenticatedUser?.id)
                case .footprints:
                    TasteFootprintsView(currentUserID: authenticatedUser?.id)
                }
            }
            .navigationDestination(isPresented: $isShowingSettings) {
                settingsDestination
            }
            .sheet(isPresented: $isEditingProfile) {
                if let activeProfile {
                    ProfileEditorSheet(profile: activeProfile, avatarPhoto: avatarPhoto)
                }
            }
            .sheet(item: $socialHubSection, onDismiss: {
                Task { await loadSocialStatistics() }
            }) { initialSection in
                if let userID = authenticatedUser?.id {
                    SocialHubView(
                        currentUserID: userID, api: authServices.socialAPI,
                        communityAPI: authServices.communityAPI,
                        collaborationAPI: authServices.socialCollaborationAPI,
                        interactionAPI: authServices.socialCollaborationAPI,
                        safetyAPI: authServices.releaseSafetyAPI,
                        photoAPI: authServices.photoAPI,
                        restaurantListAPI: authServices.restaurantListAPI,
                        initialSection: initialSection
                    )
                }
            }
            .task { await restoreSessionAndProfile() }
        }
    }

    private var primaryActions: some View {
        ProfileDashboardSection(title: "") {
            LazyVGrid(columns: dashboardColumns(count: 2), spacing: 10) {
                NavigationLink {
                    RestaurantRouletteScreen(preferredCity: activeProfile?.city)
                } label: {
                    ProfileDashboardTile(
                        emoji: "🎯",
                        title: "今天吃什么",
                        detail: "转出今天这一家",
                        tint: RouletteTheme.brandSoft
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile-restaurant-roulette-entry")

                NavigationLink {
                    TasteProfileAnalysisScreen()
                } label: {
                    ProfileDashboardTile(
                        emoji: "🍽️",
                        title: "我的口味档案",
                        detail: "看懂真实味觉偏好",
                        tint: TasteMapAnalysisTheme.ingredientRedSoft,
                        premiumFeature: .fullTasteProfile
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile-taste-analysis-entry")
            }
        }
        .accessibilityIdentifier("profile-primary-actions")
    }

    private var memoriesSection: some View {
        ProfileDashboardSection(title: "回味") {
            LazyVGrid(columns: dashboardColumns(count: 3), spacing: 8) {
                NavigationLink {
                    MonthlyRecapAnalysisScreen()
                } label: {
                    ProfileCompactTile(
                        emoji: "🗓️", title: "本月回顾",
                        tint: TasteMapAnalysisTheme.brandSoft,
                        premiumFeature: .monthlyRecap
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile-monthly-recap-entry")

                NavigationLink {
                    AnnualRecapAnalysisScreen()
                } label: {
                    ProfileCompactTile(
                        emoji: "🧭", title: "年度回顾",
                        tint: TasteMapAnalysisTheme.leafGreenSoft,
                        premiumFeature: .annualRecap
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile-annual-recap-entry")

                NavigationLink {
                    OnThisDayScreen(
                        currentUserID: authenticatedUser?.id ?? OnThisDayInput.localOwnerID,
                        context: onThisDayContext
                    )
                } label: {
                    ProfileCompactTile(
                        emoji: "🍲", title: "那年今日",
                        tint: TasteMapAnalysisTheme.caramelSoft
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile-on-this-day-entry")
            }
        }
        .accessibilityIdentifier("profile-memories-section")
    }

    private var listsSection: some View {
        ProfileDashboardSection(title: "我的食单") {
            if let userID = authenticatedUser?.id {
                NavigationLink {
                    RestaurantListsOverviewView(
                        currentUserID: userID,
                        photoAPI: authServices.photoAPI
                    )
                } label: {
                    ProfileCompactRow(
                        emoji: "📋",
                        title: "我的榜单",
                        detail: activeListCount == 0 ? "整理主题餐厅清单" : "\(activeListCount) 份榜单"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile-restaurant-lists-entry")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile-lists-section")
    }

    private var insightsSection: some View {
        ProfileDashboardSection(title: "发现与洞察") {
            LazyVGrid(columns: dashboardColumns(count: 2), spacing: 10) {
                NavigationLink {
                    DiningCompanionAnalysisScreen()
                } label: {
                    ProfileDashboardTile(
                        emoji: "🥢", title: "最佳饭搭子", detail: "看看和谁最合拍",
                        tint: TasteMapAnalysisTheme.leafGreenSoft,
                        premiumFeature: .companionAnalysis
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile-companion-analysis-entry")

                NavigationLink {
                    RecommendationSourceAnalysisScreen()
                } label: {
                    ProfileDashboardTile(
                        emoji: "🧾", title: "谁最会种草", detail: "谁最靠谱，谁最坑",
                        tint: TasteMapAnalysisTheme.caramelSoft,
                        premiumFeature: .recommendationSourceAnalysis
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile-recommendation-source-analysis-entry")
            }
        }
        .accessibilityIdentifier("profile-insights-section")
    }

    private func dashboardColumns(count: Int) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible()),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : count
        )
    }

    private var tasteFootprintsSection: some View {
        ProfileDashboardSection(title: "味觉足迹") {
            Button { browseDestination = .footprints } label: {
                ProfileCompactRow(
                    emoji: "🗺️",
                    title: "查看味觉时间线",
                    detail: tasteFootprintCount == 0 ? "从第一次到访或收藏开始记录" : "\(tasteFootprintCount) 条味觉操作"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile-taste-footprints-entry")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile-taste-footprints-section")
    }

    private var settingsEntry: some View {
        NavigationLink {
            settingsDestination
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "gearshape")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text("设置").font(.headline).foregroundStyle(.primary)
                    Text(authenticatedUser == nil
                        ? "账户、权限、存储与关于"
                        : "同步：\(syncCoordinator.presentation.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(16)
            .tasteMapCoreCard(radius: 20)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile-settings-entry")
    }

    private var settingsDestination: some View {
        TasteMapSettingsView(
            authenticatedUser: authenticatedUser,
            profile: activeProfile,
            avatarPhoto: avatarPhoto,
            logoutAction: SettingsLogoutAction(perform: { await logout() }),
            accountDeletedAction: SettingsAccountDeletedAction(perform: { await accountDeletionDidComplete() }),
            permissionOverride: settingsPermissionOverride,
            syncPresentationOverride: settingsSyncPresentationOverride
        )
    }

    private var settingsPermissionOverride: SettingsPermissionSnapshot? {
#if DEBUG
        TasteMapUITestFixtures.settingsPermissionOverride
#else
        nil
#endif
    }

    private var settingsSyncPresentationOverride: SyncPresentation? {
#if DEBUG
        TasteMapUITestFixtures.settingsSyncPresentationOverride
#else
        nil
#endif
    }

    private var onThisDayContext: OnThisDayContext {
#if DEBUG
        TasteMapUITestFixtures.onThisDayContextOverride ?? .live()
#else
        .live()
#endif
    }

    @MainActor
    private func restoreSessionAndProfile() async {
#if DEBUG
        if TasteMapUITestFixtures.usesProfileFixture {
            let fixture = AuthenticatedUserV1(
                id: TasteMapUITestFixtures.profileUserID,
                email: "private-ui-fixture@example.test"
            )
            authenticatedUser = fixture
            authServices.activateLocalAccount(fixture)
            try? LocalAccountOwnershipMigrator(context: modelContext).activate(userID: fixture.id)
            ensureLocalProfile(for: fixture)
            if let override = TasteMapUITestFixtures.premiumOverride {
                _ = premiumEntitlementService.setDevelopmentOverride(override)
            }
            await premiumEntitlementService.activate(userID: fixture.id, refreshFromServer: false)
            socialStatistics = TasteMapUITestFixtures.profileSocialStatisticsOverride ?? .zero
            return
        }
#endif
        authenticatedUser = await authServices.sessionManager.restoredUser()
        guard let authenticatedUser else { return }
        authServices.activateLocalAccount(authenticatedUser)
        try? LocalAccountOwnershipMigrator(context: modelContext).activate(userID: authenticatedUser.id)
        await syncCoordinator.sessionDidBecomeAvailable(userID: authenticatedUser.id)
        await premiumEntitlementService.activate(userID: authenticatedUser.id)
        ensureLocalProfile(for: authenticatedUser)
        await loadSocialStatistics()
    }

    @MainActor
    private func ensureLocalProfile(for user: AuthenticatedUserV1) {
        do {
            _ = try LocalUserProfileStore(context: modelContext).ensureProfile(
                tasteMapUserID: user.id
            )
        } catch {
            authMessage = "失败：个人资料暂时无法初始化。"
        }
    }

    @MainActor
    private func signIn() async {
        guard let anchor = presentationAnchor else {
            authMessage = "失败：无法取得登录窗口。"
            return
        }
        await performAuthOperation {
            let user = try await authServices.appleSignIn.signIn(presentationAnchor: anchor)
            authenticatedUser = user
            authServices.activateLocalAccount(user)
            try LocalAccountOwnershipMigrator(context: modelContext).activate(userID: user.id)
            await syncCoordinator.sessionDidBecomeAvailable(userID: user.id)
            await premiumEntitlementService.activate(userID: user.id)
            ensureLocalProfile(for: user)
            await loadSocialStatistics()
            return "Apple 登录和同步成功。"
        }
    }

    @MainActor
    private func logout() async -> String {
        isRunningAuthOperation = true
        defer { isRunningAuthOperation = false }
        let result: String
        do {
            try await authServices.sessionManager.logout()
            result = "已退出并清理 Keychain session。"
        } catch {
            result = "已从此设备退出；服务端会话撤销暂时未确认。"
        }
        try? LocalSocialStore(context: modelContext).purgeAllSocialDerivedCaches()
        try? LocalRestaurantListStore(context: modelContext).purgePublicCache()
        authenticatedUser = nil
        authServices.endLocalAccountSession()
        socialStatistics = .zero
        premiumEntitlementService.sessionDidEnd()
        syncCoordinator.sessionDidEnd()
        authMessage = result
        return result
    }

    @MainActor
    private func accountDeletionDidComplete() async {
        try? LocalSocialStore(context: modelContext).purgeAllSocialDerivedCaches()
        try? LocalRestaurantListStore(context: modelContext).purgePublicCache()
        authenticatedUser = nil
        authServices.endLocalAccountSession()
        socialStatistics = .zero
        premiumEntitlementService.sessionDidEnd()
        syncCoordinator.sessionDidEnd()
        authMessage = "Taste Map 账户已永久删除。"
    }

    @MainActor
    private func loadSocialStatistics() async {
        guard let userID = authenticatedUser?.id else {
            socialStatistics = .zero
            return
        }
#if DEBUG
        if let fixture = TasteMapUITestFixtures.profileSocialStatisticsOverride {
            socialStatistics = fixture
            return
        }
#endif
        socialStatistics = ProfileSocialStatisticsLoader.cached(
            context: modelContext,
            currentUserID: userID
        )
        socialStatistics = await ProfileSocialStatisticsLoader.load(
            api: authServices.socialAPI,
            context: modelContext,
            currentUserID: userID
        )
    }

    @MainActor
    private func performAuthOperation(_ operation: () async throws -> String) async {
        isRunningAuthOperation = true
        defer { isRunningAuthOperation = false }
        do { authMessage = try await operation() }
        catch { authMessage = "失败：操作未完成，请稍后重试。" }
    }

    private var presentationAnchor: ASPresentationAnchor? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}

struct ProfileBasicStatistics: Equatable {
    let visitedRestaurantCount: Int
    let wantToGoRestaurantCount: Int
    let visitCount: Int
    let averageRating: Double?
    let totalSpend: Decimal?

    init(restaurants: [Restaurant], visits: [Visit]) {
        let activeRestaurants = restaurants.filter { $0.deletedAt == nil }
        let activeRestaurantIDs = Set(activeRestaurants.map(\.id))
        let activeVisits = visits.filter {
            $0.deletedAt == nil && activeRestaurantIDs.contains($0.restaurantId)
        }
        let statusPartition = RestaurantVisitStatePolicy.partition(
            restaurants: activeRestaurants,
            visits: activeVisits
        )
        visitedRestaurantCount = statusPartition.visited.count
        wantToGoRestaurantCount = statusPartition.wantToGo.count
        visitCount = activeVisits.count
        let ratings = activeVisits.compactMap(\.rating)
        averageRating = ratings.isEmpty ? nil : ratings.reduce(0, +) / Double(ratings.count)
        let spend = activeVisits.compactMap(\.resolvedActualSpend)
        totalSpend = spend.isEmpty ? nil : spend.reduce(Decimal.zero, +)
    }

    init(
        visitedRestaurantCount: Int,
        wantToGoRestaurantCount: Int,
        visitCount: Int,
        averageRating: Double?,
        totalSpend: Decimal?
    ) {
        self.visitedRestaurantCount = visitedRestaurantCount
        self.wantToGoRestaurantCount = wantToGoRestaurantCount
        self.visitCount = visitCount
        self.averageRating = averageRating
        self.totalSpend = totalSpend
    }
}

private struct ProfileIdentityCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var didCopyUserID = false
    let profile: UserProfile?
    let avatarPhoto: PhotoAsset?
    let isSignedIn: Bool
    let shareEntityID: String?
    let membershipStatus: MembershipStatus
    let socialStatistics: ProfileSocialStatistics
    let onEdit: () -> Void
    let onSignIn: () -> Void
    let onPremium: () -> Void
    let onFollowing: () -> Void
    let onFollowers: () -> Void
    let onDiscover: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 11) {
            if isSignedIn {
                profileHeaderControls
                avatar
                identityContent
            } else if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    avatar
                    identityContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: 13) {
                    avatar
                    identityContent
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, isSignedIn ? TasteMapDesignTokens.ProfileSummary.statisticInset : 12)
        .background(
            LinearGradient(
                colors: [TasteMapCoreTheme.brandSoft, TasteMapCoreTheme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TasteMapCoreTheme.border.opacity(0.9))
        }
        .shadow(color: TasteMapCoreTheme.cardShadow, radius: 8, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile-identity-card")
    }

    private var profileHeaderControls: some View {
        HStack(spacing: 12) {
            Button(action: onDiscover) {
                Label("添加好友", systemImage: "person.badge.plus")
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile-social-entry")
            Spacer(minLength: 0)
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")
            .accessibilityIdentifier("profile-settings-header-entry")
        }
    }

    private var avatar: some View {
        ProfileAvatarView(profile: profile, photo: avatarPhoto)
            .frame(width: isSignedIn ? 76 : 58, height: isSignedIn ? 76 : 58)
    }

    @ViewBuilder
    private var identityContent: some View {
        if let profile, isSignedIn {
            VStack(alignment: .center, spacing: 6) {
                HStack(spacing: 7) {
                    Text(profile.displayName)
                        .font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                    if membershipStatus == .premium || membershipStatus == .gracePeriod {
                        Button(action: onPremium) {
                            PremiumBurgerBadge().frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Taste Map Premium 已开通，查看会员状态")
                        .accessibilityIdentifier("profile-premium-badge-entry")
                    }
                }
                Button {
                    UIPasteboard.general.string = TasteMapPublicUserID.numeric(from: profile.tasteMapUserID)
                    didCopyUserID = true
                } label: {
                    HStack(spacing: 5) {
                        Text("ID \(TasteMapPublicUserID.numeric(from: profile.tasteMapUserID))")
                            .font(.caption2.monospacedDigit())
                        Image(systemName: didCopyUserID ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(didCopyUserID ? "用户 ID 已复制" : "复制用户 ID")
                .accessibilityValue("ID \(TasteMapPublicUserID.numeric(from: profile.tasteMapUserID))")
                .accessibilityIdentifier("profile-user-id")
                ProfileConnectionMetrics(
                    followingCount: socialStatistics.followingCount,
                    followerCount: socialStatistics.followerCount,
                    isLoading: false,
                    identifierPrefix: "profile",
                    onFollowing: onFollowing,
                    onFollowers: onFollowers
                )
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { profileMetadata(profile) }
                    VStack(alignment: .center, spacing: 5) { profileMetadata(profile) }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)

                if membershipStatus == .free || membershipStatus == .expired || shareEntityID != nil {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { profileActions }
                        VStack(alignment: .center, spacing: 8) { profileActions }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("记录属于你的每一顿")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("登录后查看个人档案、统计与回味。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onSignIn) {
                    Label("使用 Apple 登录", systemImage: "apple.logo")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("profile-sign-in-button")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func profileMetadata(_ profile: UserProfile) -> some View {
        if !profile.city.isEmpty {
            Label(profile.city, systemImage: "building.2")
                .accessibilityIdentifier("profile-city-text")
        }
        Label {
            Text("加入于 \(TasteMapDisplayDate.yearMonth(profile.createdAt))")
        } icon: {
            Image(systemName: "calendar.badge.checkmark")
        }
    }

    @ViewBuilder
    private var profileActions: some View {
        if membershipStatus == .free || membershipStatus == .expired {
            Button("Premium", action: onPremium)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("profile-premium-entry")
        }
        if let shareEntityID {
            PublicShareButton(entityType: .profile, entityID: shareEntityID) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("分享我的公开主页")
        }
    }

}

/// Shared compact social identity metadata for both the owner Profile and a
/// public Profile. Public counts are genuinely remote, so the component keeps
/// loading and unavailable states distinct instead of inventing zeroes or
/// rendering ambiguous dashes.
struct ProfileConnectionMetrics: View {
    let followingCount: Int?
    let followerCount: Int?
    let isLoading: Bool
    let identifierPrefix: String
    var onFollowing: (() -> Void)?
    var onFollowers: (() -> Void)?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { metrics }
            VStack(spacing: 4) { metrics }
        }
    }

    @ViewBuilder
    private var metrics: some View {
        metric(
            "关注", value: followingCount, systemImage: "person.2",
            identifier: "\(identifierPrefix)-following-stat", action: onFollowing
        )
        metric(
            "粉丝", value: followerCount, systemImage: "person.2.fill",
            identifier: "\(identifierPrefix)-followers-stat", action: onFollowers
        )
    }

    @ViewBuilder
    private func metric(
        _ title: String,
        value: Int?,
        systemImage: String,
        identifier: String,
        action: (() -> Void)?
    ) -> some View {
        if let action {
            Button(action: action) {
                metricLabel(title, value: value, systemImage: systemImage)
            }
            .buttonStyle(.plain)
            .frame(minHeight: 36)
            .accessibilityLabel(accessibilityLabel(title, value: value, isAction: true))
            .accessibilityIdentifier(identifier)
        } else {
            metricLabel(title, value: value, systemImage: systemImage)
                .frame(minHeight: 36)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel(title, value: value, isAction: false))
                .accessibilityIdentifier(identifier)
        }
    }

    private func metricLabel(_ title: String, value: Int?, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            if let value {
                Text("\(value) \(title)")
                    .monospacedDigit()
            } else if isLoading {
                ProgressView().controlSize(.mini)
                Text(title)
            } else {
                Text("\(title)暂不可用")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(TasteMapCoreTheme.brandDeep)
        .lineLimit(1)
    }

    private func accessibilityLabel(_ title: String, value: Int?, isAction: Bool) -> String {
        if let value { return "\(title) \(value)\(isAction ? "，查看" : "")" }
        return isLoading ? "\(title)数据正在加载" : "\(title)数据暂时无法加载"
    }
}

/// The owner Profile and its previews share one compact summary rhythm.
/// Other Dashboard sections keep their existing independent spacing.
private struct ProfileSummaryTemplate<Header: View, Statistics: View, Actions: View>: View {
    let showsStatistics: Bool
    @ViewBuilder let header: Header
    @ViewBuilder let statistics: Statistics
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: TasteMapDesignTokens.Spacing.content) { header }
            if showsStatistics {
                statistics.padding(.top, TasteMapDesignTokens.ProfileSummary.identityGap)
                actions.padding(.top, TasteMapDesignTokens.ProfileSummary.nextGap)
            }
        }
    }
}

private struct ProfileStatisticsSection: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let statistics: ProfileBasicStatistics
    let onVisited: () -> Void
    let onWantToGo: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) { statisticsContent(vertical: true) }
            } else {
                HStack(spacing: 0) { statisticsContent(vertical: false) }
            }
        }
        .padding(.vertical, TasteMapDesignTokens.ProfileSummary.statisticInset)
        .tasteMapCoreCard(radius: 18)
    }

    @ViewBuilder
    private func statisticsContent(vertical: Bool) -> some View {
            Button(action: onVisited) {
                statistic(
                    "去过", value: "\(statistics.visitedRestaurantCount)",
                    systemImage: RestaurantStatus.visited.systemImage
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile-stat-visited")
            divider(vertical: vertical)
            Button(action: onWantToGo) {
                statistic(
                    RestaurantStatus.wantToGo.title, value: "\(statistics.wantToGoRestaurantCount)",
                    systemImage: "bookmark.fill"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile-stat-want")
            divider(vertical: vertical)
            statistic(
                "总消费",
                value: statistics.totalSpend.map(Self.currencyString) ?? "—",
                systemImage: "receipt.fill"
            )
            .accessibilityIdentifier("profile-stat-spend")
    }

    @ViewBuilder
    private func divider(vertical: Bool) -> some View {
        if vertical {
            Divider().padding(.horizontal, 14)
        } else {
            Divider().frame(height: 36)
        }
    }

    private func statistic(_ title: String, value: String, systemImage: String) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TasteMapCoreTheme.brand)
                    .accessibilityHidden(true)
                Text(value)
                    .font(.subheadline.bold())
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: TasteMapDesignTokens.ProfileSummary.statisticMinimumHeight)
    }

    nonisolated private static func currencyString(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        formatter.locale = .current
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "¥\(value)"
    }
}

private struct ProfileDashboardSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: title.isEmpty ? 0 : 9) {
            if !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(TasteMapCoreTheme.textPrimary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProfileDashboardTile: View {
    let emoji: String
    let title: String
    let detail: String
    let tint: Color
    var premiumFeature: PremiumFeature?

    var body: some View {
        HStack(spacing: 10) {
            FoodDiningVisualIcon(
                kind: FoodDiningVisualLibrary.kind(semanticID: title, legacySymbol: emoji),
                usage: .decorative,
                size: 38,
                foregroundColor: TasteMapCoreTheme.brandDeep,
                backgroundColor: tint
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let premiumFeature {
                    PremiumFeatureInlineBadge(feature: premiumFeature)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .tasteMapCoreCard(radius: 17)
    }
}

private struct ProfileCompactTile: View {
    let emoji: String
    let title: String
    let tint: Color
    var premiumFeature: PremiumFeature?

    var body: some View {
        VStack(spacing: 7) {
            FoodDiningVisualIcon(
                kind: FoodDiningVisualLibrary.kind(semanticID: title, legacySymbol: emoji),
                usage: .decorative,
                size: 36,
                foregroundColor: TasteMapCoreTheme.brandDeep,
                backgroundColor: tint
            )
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let premiumFeature {
                PremiumFeatureInlineBadge(feature: premiumFeature)
                    .scaleEffect(0.88)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 78)
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .tasteMapCoreCard(radius: 16)
    }
}

private struct ProfileCompactRow: View {
    let emoji: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 11) {
            FoodDiningVisualIcon(
                kind: FoodDiningVisualLibrary.kind(semanticID: title, legacySymbol: emoji),
                usage: .decorative,
                size: 34,
                foregroundColor: TasteMapCoreTheme.brandDeep,
                backgroundColor: TasteMapCoreTheme.brandSoft
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .tasteMapCoreCard(radius: 16)
    }
}

enum ProfileEditorDestination: String, Identifiable, CaseIterable {
    case all, displayName, visibility

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "编辑资料"
        case .displayName: "修改显示名称"
        case .visibility: "主页可见范围"
        }
    }

    var editsIdentity: Bool { self == .all || self == .displayName }
    var editsVisibility: Bool { self == .all || self == .visibility }
}

struct ProfileEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.photoTransferCoordinator) private var photoTransferCoordinator
    @Environment(PremiumEntitlementService.self) private var premiumEntitlementService
    let profile: UserProfile
    let avatarPhoto: PhotoAsset?
    let destination: ProfileEditorDestination
    @FocusState private var isNameFocused: Bool
    @State private var displayName: String
    @State private var city: String
    @State private var selectedPreset: ProfileAvatarPreset
    @State private var avatarPhotoID: String?
    @State private var visibility: ProfileVisibility
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(profile: UserProfile, avatarPhoto: PhotoAsset?, destination: ProfileEditorDestination = .all) {
        self.profile = profile
        self.avatarPhoto = avatarPhoto
        self.destination = destination
        _displayName = State(initialValue: profile.displayName)
        _city = State(initialValue: profile.city)
        _selectedPreset = State(initialValue: profile.avatarPreset)
        _avatarPhotoID = State(initialValue: profile.avatarPhotoID)
        _visibility = State(initialValue: profile.visibility)
    }

    var body: some View {
        NavigationStack {
            Form {
                if destination == .all {
                  Section("头像") {
                    HStack {
                        Spacer()
                        editorAvatar.frame(width: 104, height: 104).clipShape(Circle())
                        Spacer()
                    }
                    switch premiumEntitlementService.access(for: .customAvatar) {
                    case .allowed:
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("从照片中选择", systemImage: "photo.on.rectangle")
                        }
                        .accessibilityIdentifier("profile-avatar-picker")
                    case .denied:
                        Button {
                            premiumEntitlementService.openPaywall(from: .feature(.customAvatar))
                        } label: {
                            Label("Premium 可上传自定义头像", systemImage: "lock")
                        }
                        .accessibilityIdentifier("profile-avatar-premium-entry")
                    case .loading:
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在确认头像权益…")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(ProfileAvatarPreset.allCases) { preset in
                                Button {
                                    selectedPreset = preset
                                    avatarPhotoID = nil
                                    selectedImageData = nil
                                    pickerItem = nil
                                } label: {
                                    VStack(spacing: 5) {
                                        PresetProfileAvatarView(preset: preset)
                                            .frame(width: 58, height: 58)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(
                                                selectedPreset == preset && avatarPhotoID == nil
                                                    ? Color.accentColor : .clear,
                                                lineWidth: 3
                                            ))
                                        Text(preset.title).font(.caption2)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("profile-avatar-preset-\(preset.rawValue)")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.hidden)
                  }
                }
                if destination.editsIdentity {
                  Section("个人资料") {
                    TextField("显示名称", text: $displayName)
                        .textInputAutocapitalization(.words)
                        .focused($isNameFocused)
                        .accessibilityIdentifier("profile-display-name")
                    if destination == .all {
                        TextField("城市（可选）", text: $city)
                            .accessibilityIdentifier("profile-city")
                    }
                  }
                }
                if destination.editsVisibility {
                  Section("个人主页可见范围") {
                    TasteMapSegmentedControl(
                        selection: $visibility,
                        items: ProfileVisibility.allCases.map {
                            .init($0, title: $0.title)
                        },
                        accessibilityIdentifier: "profile-visibility"
                    )
                    Text("公开资料只包含头像、显示名称、城市和基于公开到访计算的统计。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                  }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .disabled(isSaving)
            .navigationTitle(destination.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    TasteMapReturnButton { dismiss() }
                        .disabled(isSaving)
                        .accessibilityIdentifier("profile-back-button")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(isSaving)
                        .accessibilityIdentifier("profile-save-button")
                }
            }
            .overlay { if isSaving { ProgressView().controlSize(.large) } }
            .task { isNameFocused = destination == .displayName }
            .task(id: pickerItem) {
                selectedImageData = try? await pickerItem?.loadTransferable(type: Data.self)
                if selectedImageData != nil { avatarPhotoID = nil }
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    @ViewBuilder
    private var editorAvatar: some View {
        if let selectedImageData, let image = UIImage(data: selectedImageData) {
            Image(uiImage: image).resizable().scaledToFill()
        } else if avatarPhotoID != nil {
            ProfileAvatarView(profile: profile, photo: avatarPhoto)
        } else {
            PresetProfileAvatarView(preset: selectedPreset)
        }
    }

    @MainActor
    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            var newAvatarPhotoID = avatarPhotoID
            if let selectedImageData {
                guard let photoTransferCoordinator else { throw PhotoImportError.encodingFailed }
                let prepared = try await photoTransferCoordinator.preparePhoto(data: selectedImageData)
                do {
                    let photo = try photoTransferCoordinator.attachPreparedAvatar(
                        prepared,
                        ownerUserID: profile.tasteMapUserID
                    )
                    newAvatarPhotoID = photo.remoteID ?? photo.id.uuidString.lowercased()
                } catch {
                    await photoTransferCoordinator.discardPrepared(prepared)
                    throw error
                }
            }
            try LocalUserProfileStore(context: modelContext).update(
                profile,
                displayName: destination.editsIdentity ? displayName : profile.displayName,
                bio: profile.bio,
                city: destination == .all ? city : profile.city,
                avatarPhotoID: destination == .all ? newAvatarPhotoID : profile.avatarPhotoID,
                avatarPreset: destination == .all ? selectedPreset : profile.avatarPreset,
                visibility: destination.editsVisibility ? visibility : profile.visibility
            )
            photoTransferCoordinator?.resumePendingTransfers()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "个人资料保存失败，请重试。"
        }
    }
}

#if DEBUG
private struct ProfilePreviewScreen: View {
    let profile: UserProfile
    let statistics: ProfileBasicStatistics
    let sync: SyncPresentation
    var photo: PhotoAsset?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ProfileSummaryTemplate(showsStatistics: true) {
                    ProfileIdentityCard(
                        profile: profile,
                        avatarPhoto: photo,
                        isSignedIn: true,
                        shareEntityID: profile.tasteMapUserID,
                        membershipStatus: .free,
                        socialStatistics: .init(friendCount: 8, followingCount: 18, followerCount: 9),
                        onEdit: {},
                        onSignIn: {},
                        onPremium: {},
                        onFollowing: {},
                        onFollowers: {},
                        onDiscover: {},
                        onSettings: {}
                    )
                } statistics: {
                    ProfileStatisticsSection(
                        statistics: statistics,
                        onVisited: {},
                        onWantToGo: {}
                    )
                } actions: {
                    ProfileCompactRow(
                        emoji: "🗺️",
                        title: "查看到访时间线",
                        detail: "\(statistics.visitCount) 次独立到访"
                    )
                }
                SyncStatusView(presentation: sync)
                    .padding(18)
                    .tasteMapCoreCard(radius: 20)
            }
            .padding(18)
        }
        .background(TasteMapCoreTheme.page)
    }
}

private enum ProfilePreviewFixtures {
    static func profile(
        name: String = "Lafayette",
        bio: String = "认真吃饭，也认真记住每一家值得回去的小店。",
        city: String = "杭州",
        preset: ProfileAvatarPreset = .otter,
        status: SyncStatus = .synced
    ) -> UserProfile {
        UserProfile(
            tasteMapUserID: "tm_preview_user",
            displayName: name,
            bio: bio,
            city: city,
            avatarPreset: preset,
            visibility: .public,
            syncStatus: status
        )
    }

    static let fullStatistics = ProfileBasicStatistics(
        visitedRestaurantCount: 42,
        wantToGoRestaurantCount: 18,
        visitCount: 67,
        averageRating: 4.4,
        totalSpend: 12_860
    )
    static let emptyStatistics = ProfileBasicStatistics(
        visitedRestaurantCount: 0,
        wantToGoRestaurantCount: 0,
        visitCount: 0,
        averageRating: nil,
        totalSpend: nil
    )
    static let synced = SyncPresentation(
        phase: .synced, pendingCount: 0, pendingPhotoCount: 0,
        failedPhotoCount: 0, conflictCount: 0, lastSyncedAt: .now
    )
}

#Preview("完整资料 · 默认头像") {
    ProfilePreviewScreen(
        profile: ProfilePreviewFixtures.profile(),
        statistics: ProfilePreviewFixtures.fullStatistics,
        sync: ProfilePreviewFixtures.synced
    )
}

#Preview("新用户 · 无记录 · 无 Bio") {
    ProfilePreviewScreen(
        profile: ProfilePreviewFixtures.profile(name: "Taste Map 用户", bio: "", city: "", preset: .polarBear),
        statistics: ProfilePreviewFixtures.emptyStatistics,
        sync: ProfilePreviewFixtures.synced
    )
}

#Preview("长名字与长简介") {
    ProfilePreviewScreen(
        profile: ProfilePreviewFixtures.profile(
            name: "一位喜欢周末沿着城市慢慢寻找好吃小店的人 🍜",
            bio: "从街边小馆到纪念日餐厅都认真记录；如果一道菜值得专程再去，就一定会在这里留下它的故事。",
            city: "上海市 · 杭州市"
        ),
        statistics: ProfilePreviewFixtures.fullStatistics,
        sync: ProfilePreviewFixtures.synced
    )
}

#Preview("Offline pending sync") {
    ProfilePreviewScreen(
        profile: ProfilePreviewFixtures.profile(status: .pending),
        statistics: ProfilePreviewFixtures.fullStatistics,
        sync: SyncPresentation(
            phase: .waitingForNetwork, pendingCount: 1, pendingPhotoCount: 1,
            failedPhotoCount: 0, conflictCount: 0, lastSyncedAt: nil
        )
    )
}

#Preview("Profile sync failed") {
    ProfilePreviewScreen(
        profile: ProfilePreviewFixtures.profile(status: .failed),
        statistics: ProfilePreviewFixtures.fullStatistics,
        sync: SyncPresentation(
            phase: .failed, pendingCount: 1, pendingPhotoCount: 0,
            failedPhotoCount: 0, conflictCount: 0, lastSyncedAt: nil
        )
    )
}

#Preview("自定义头像占位") {
    ProfilePreviewScreen(
        profile: ProfilePreviewFixtures.profile(),
        statistics: ProfilePreviewFixtures.fullStatistics,
        sync: ProfilePreviewFixtures.synced,
        photo: PhotoAsset(kind: .avatar, mimeType: "image/jpeg", byteSize: 1)
    )
}

#Preview("小屏设备", traits: .fixedLayout(width: 320, height: 568)) {
    ProfilePreviewScreen(
        profile: ProfilePreviewFixtures.profile(name: "小林", bio: "", city: "北京", preset: .cat),
        statistics: ProfilePreviewFixtures.emptyStatistics,
        sync: ProfilePreviewFixtures.synced
    )
}

#Preview("大字体") {
    ProfilePreviewScreen(
        profile: ProfilePreviewFixtures.profile(),
        statistics: ProfilePreviewFixtures.fullStatistics,
        sync: ProfilePreviewFixtures.synced
    )
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
