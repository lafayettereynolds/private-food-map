import AuthenticationServices
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.photoTransferCoordinator) private var photoTransferCoordinator
    @Environment(NativeAuthServices.self) private var authServices
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Query private var restaurants: [Restaurant]
    @Query private var visits: [Visit]
    @Query private var profiles: [UserProfile]
    @Query private var photos: [PhotoAsset]
    @State private var authenticatedUser: AuthenticatedUserV1?
    @State private var isRunningAuthOperation = false
    @State private var authMessage: String?
    @State private var isEditingProfile = false
    @State private var isShowingSocialHub = false

    private var activeRestaurants: [Restaurant] { restaurants.filter { $0.deletedAt == nil } }
    private var activeVisits: [Visit] { visits.filter { $0.deletedAt == nil } }
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ProfileIdentityCard(
                        profile: activeProfile,
                        avatarPhoto: avatarPhoto,
                        isSignedIn: authenticatedUser != nil,
                        onEdit: { isEditingProfile = true },
                        onSignIn: { Task { await signIn() } }
                    )
                    ProfileStatisticsSection(statistics: statistics)
                    ProfileContentLinks(
                        visitedCount: statistics.visitedRestaurantCount,
                        wantToGoCount: statistics.wantToGoRestaurantCount
                    )
                    if let userID = authenticatedUser?.id {
                        Button { isShowingSocialHub = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.2.badge.plus")
                                    .frame(width: 24).foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("好友与关注").font(.headline).foregroundStyle(.primary)
                                    Text("搜索用户、处理好友请求和查看关注关系")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(16)
                            .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile-social-entry")
                        .sheet(isPresented: $isShowingSocialHub) {
                            SocialHubView(
                                currentUserID: userID, api: authServices.socialAPI,
                                communityAPI: authServices.communityAPI,
                                photoAPI: authServices.photoAPI
                            )
                        }
                    }
                    accountAndSyncCard
                    if activeRestaurants.isEmpty {
                        ContentUnavailableView(
                            "还没有美食记录",
                            systemImage: "fork.knife.circle",
                            description: Text("保存第一次到访后，你的真实记录会显示在这里。")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("我的")
            .sheet(isPresented: $isEditingProfile) {
                if let activeProfile {
                    ProfileEditorSheet(profile: activeProfile, avatarPhoto: avatarPhoto)
                }
            }
            .task { await restoreSessionAndProfile() }
        }
    }

    private var accountAndSyncCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("账号与同步", systemImage: "person.crop.circle.badge.checkmark")
                .font(.headline)
            if let authenticatedUser {
                if let email = authenticatedUser.email {
                    LabeledContent("Apple 邮箱", value: email)
                        .foregroundStyle(.secondary)
                }
                SyncStatusView(presentation: syncCoordinator.presentation)
                Button(syncCoordinator.presentation.allowsRetry ? "重试同步" : "立即同步") {
                    Task {
                        if syncCoordinator.presentation.allowsRetry {
                            await syncCoordinator.retryNow()
                        } else {
                            await syncCoordinator.synchronizeNow()
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(syncCoordinator.presentation.phase == .syncing)
                .accessibilityIdentifier("profile-sync-button")
#if DEBUG
                Button("验证 Token 刷新") { Task { await forceRefresh() } }
                    .font(.subheadline)
#endif
                Button("退出登录", role: .destructive) { Task { await logout() } }
                    .font(.subheadline)
            } else {
                Text("登录后，资料和记录会在你的设备之间安全同步。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if isRunningAuthOperation { ProgressView() }
            if let authMessage {
                Text(authMessage)
                    .font(.footnote)
                    .foregroundStyle(authMessage.hasPrefix("失败") ? .red : .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
            ensureLocalProfile(for: fixture)
            return
        }
#endif
        authenticatedUser = await authServices.sessionManager.restoredUser()
        guard let authenticatedUser else { return }
        await syncCoordinator.sessionDidBecomeAvailable()
        ensureLocalProfile(for: authenticatedUser)
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
            await syncCoordinator.sessionDidBecomeAvailable()
            ensureLocalProfile(for: user)
            return "Apple 登录和同步成功。"
        }
    }

    @MainActor
    private func forceRefresh() async {
        await performAuthOperation {
            authenticatedUser = try await authServices.sessionManager.forceRefresh()
            await syncCoordinator.sessionDidBecomeAvailable()
            return "Access/refresh token 已安全轮换。"
        }
    }

    @MainActor
    private func logout() async {
        isRunningAuthOperation = true
        defer { isRunningAuthOperation = false }
        do {
            try await authServices.sessionManager.logout()
            authMessage = "已退出并清理 Keychain session。"
        } catch {
            authMessage = "已从此设备退出；服务端会话撤销暂时未确认。"
        }
        authenticatedUser = nil
        syncCoordinator.sessionDidEnd()
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
        visitedRestaurantCount = Set(visits.map(\.restaurantId)).count
        wantToGoRestaurantCount = restaurants.filter { $0.status == .wantToGo }.count
        visitCount = visits.count
        let ratings = visits.compactMap(\.rating)
        averageRating = ratings.isEmpty ? nil : ratings.reduce(0, +) / Double(ratings.count)
        let spend = visits.compactMap(\.myActualSpend)
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
    let profile: UserProfile?
    let avatarPhoto: PhotoAsset?
    let isSignedIn: Bool
    let onEdit: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ProfileAvatarView(profile: profile, photo: avatarPhoto)
                .frame(width: 104, height: 104)
            if let profile, isSignedIn {
                VStack(spacing: 6) {
                    Text(profile.displayName)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    if !profile.bio.isEmpty {
                        Text(profile.bio)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("profile-bio-text")
                    }
                    if !profile.city.isEmpty {
                        Label(profile.city, systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("profile-city-text")
                    }
                    Text(profile.createdAt, format: .dateTime.year().month())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Button("编辑资料", action: onEdit)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("profile-edit-button")
            } else {
                Text("记录属于你的每一顿")
                    .font(.title3.bold())
                Button(action: onSignIn) {
                    Label("使用 Apple 登录", systemImage: "apple.logo")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("profile-sign-in-button")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 18)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.12), .white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
    }
}

private struct ProfileStatisticsSection: View {
    let statistics: ProfileBasicStatistics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("我的记录").font(.headline)
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                statistic("去过", value: "\(statistics.visitedRestaurantCount)", icon: "fork.knife")
                statistic("到访", value: "\(statistics.visitCount)", icon: "calendar")
                statistic(
                    "平均评分",
                    value: statistics.averageRating.map { String(format: "%.1f", $0) } ?? "未评分",
                    icon: "star.fill"
                )
                statistic(
                    "实际消费",
                    value: statistics.totalSpend.map(Self.currencyString) ?? "暂无",
                    icon: "wallet.bifold"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statistic(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(Color.accentColor)
            Text(value).font(.title3.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(15)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    nonisolated private static func currencyString(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        formatter.locale = .current
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "¥\(value)"
    }
}

private struct ProfileContentLinks: View {
    let visitedCount: Int
    let wantToGoCount: Int

    var body: some View {
        VStack(spacing: 0) {
            row("去过的餐厅", value: "\(visitedCount)", icon: "checkmark.circle.fill")
            Divider().padding(.leading, 48)
            row("想吃的餐厅", value: "\(wantToGoCount)", icon: "bookmark.fill")
        }
        .padding(.horizontal, 16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func row(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(Color.accentColor)
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .padding(.vertical, 15)
    }
}

private struct ProfileEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.photoTransferCoordinator) private var photoTransferCoordinator
    let profile: UserProfile
    let avatarPhoto: PhotoAsset?
    @State private var displayName: String
    @State private var bio: String
    @State private var city: String
    @State private var selectedPreset: ProfileAvatarPreset
    @State private var avatarPhotoID: String?
    @State private var visibility: ProfileVisibility
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(profile: UserProfile, avatarPhoto: PhotoAsset?) {
        self.profile = profile
        self.avatarPhoto = avatarPhoto
        _displayName = State(initialValue: profile.displayName)
        _bio = State(initialValue: profile.bio)
        _city = State(initialValue: profile.city)
        _selectedPreset = State(initialValue: profile.avatarPreset)
        _avatarPhotoID = State(initialValue: profile.avatarPhotoID)
        _visibility = State(initialValue: profile.visibility)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("头像") {
                    HStack {
                        Spacer()
                        editorAvatar.frame(width: 104, height: 104).clipShape(Circle())
                        Spacer()
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("从照片中选择", systemImage: "photo.on.rectangle")
                    }
                    .accessibilityIdentifier("profile-avatar-picker")
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
                Section("个人资料") {
                    TextField("显示名称", text: $displayName)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("profile-display-name")
                    TextField("城市（可选）", text: $city)
                        .accessibilityIdentifier("profile-city")
                    TextField("个人简介（可选）", text: $bio, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("profile-bio")
                }
                Section("个人主页可见范围") {
                    Picker("可见范围", selection: $visibility) {
                        ForEach(ProfileVisibility.allCases, id: \.self) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("公开资料只包含头像、显示名称、简介、城市和基于公开到访计算的统计。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("编辑资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(isSaving)
                        .accessibilityIdentifier("profile-save-button")
                }
            }
            .overlay { if isSaving { ProgressView().controlSize(.large) } }
            .task(id: pickerItem) {
                selectedImageData = try? await pickerItem?.loadTransferable(type: Data.self)
                if selectedImageData != nil { avatarPhotoID = nil }
            }
        }
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
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            var newAvatarPhotoID = avatarPhotoID
            if let selectedImageData {
                guard let photoTransferCoordinator else { throw PhotoImportError.encodingFailed }
                let prepared = try await photoTransferCoordinator.preparePhoto(data: selectedImageData)
                do {
                    let photo = try photoTransferCoordinator.attachPreparedAvatar(prepared)
                    newAvatarPhotoID = photo.remoteID ?? photo.id.uuidString.lowercased()
                } catch {
                    await photoTransferCoordinator.discardPrepared(prepared)
                    throw error
                }
            }
            try LocalUserProfileStore(context: modelContext).update(
                profile,
                displayName: displayName,
                bio: bio,
                city: city,
                avatarPhotoID: newAvatarPhotoID,
                avatarPreset: selectedPreset,
                visibility: visibility
            )
            photoTransferCoordinator?.resumePendingTransfers()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "个人资料保存失败，请重试。"
        }
    }
}

private struct ProfilePreviewScreen: View {
    let profile: UserProfile
    let statistics: ProfileBasicStatistics
    let sync: SyncPresentation
    var photo: PhotoAsset?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ProfileIdentityCard(
                    profile: profile,
                    avatarPhoto: photo,
                    isSignedIn: true,
                    onEdit: {},
                    onSignIn: {}
                )
                ProfileStatisticsSection(statistics: statistics)
                ProfileContentLinks(
                    visitedCount: statistics.visitedRestaurantCount,
                    wantToGoCount: statistics.wantToGoRestaurantCount
                )
                SyncStatusView(presentation: sync)
                    .padding(18)
                    .background(.background, in: RoundedRectangle(cornerRadius: 20))
            }
            .padding(18)
        }
        .background(Color(uiColor: .systemGroupedBackground))
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
