import SwiftData
import SwiftUI
import UIKit

struct TasteMapSettingsView: View {
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Environment(PremiumEntitlementService.self) private var premiumEntitlementService

    let authenticatedUser: AuthenticatedUserV1?
    let profile: UserProfile?
    let avatarPhoto: PhotoAsset?
    let logoutAction: SettingsLogoutAction
    var accountDeletedAction = SettingsAccountDeletedAction(perform: {})
    var releaseConfiguration: ReleaseConfiguration = .current()
    var permissionOverride: SettingsPermissionSnapshot?
    var storageOverride: SettingsStorageSnapshot?
    var syncPresentationOverride: SyncPresentation?
    var membershipStatusOverride: MembershipStatus?
    var exposesFutureArchitecture = false

    private var availability: SettingsFeatureAvailability {
        SettingsFeatureAvailability(
            releaseConfiguration: releaseConfiguration,
            purchaseCapabilities: premiumEntitlementService.productsProvider.capabilities,
            exposesFutureArchitecture: exposesFutureArchitecture
        )
    }

    private var syncPresentation: SyncPresentation {
        syncPresentationOverride ?? syncCoordinator.presentation
    }

    private var membershipStatus: MembershipStatus {
        membershipStatusOverride ?? premiumEntitlementService.membershipStatus
    }

    var body: some View {
        List {
            Section("账户") {
                NavigationLink {
                    AccountSettingsView(
                        authenticatedUser: authenticatedUser,
                        profile: profile,
                        avatarPhoto: avatarPhoto,
                        logoutAction: logoutAction,
                        accountDeletedAction: accountDeletedAction
                    )
                } label: {
                    SettingsDestinationLabel(
                        title: "账户",
                        subtitle: authenticatedUser == nil ? "未登录" : (profile?.displayName ?? "已登录"),
                        systemImage: "person.crop.circle"
                    )
                }
                .accessibilityIdentifier("settings-account-entry")
            }

            Section("数据与备份") {
                NavigationLink {
                    DataBackupSettingsView(
                        isAuthenticated: authenticatedUser != nil,
                        currentTasteMapUserID: authenticatedUser?.id,
                        allowsImport: availability.isVisible(.importData)
                    )
                } label: {
                    SettingsDestinationLabel(
                        title: "数据与备份",
                        subtitle: authenticatedUser == nil ? "登录后可导出" : "Backup v1",
                        systemImage: "externaldrive"
                    )
                }
                .accessibilityIdentifier("settings-data-backup-entry")
            }

            Section("同步") {
                NavigationLink {
                    SyncSettingsView(presentationOverride: syncPresentationOverride)
                } label: {
                    SettingsDestinationLabel(
                        title: "同步",
                        subtitle: syncPresentation.title,
                        systemImage: syncPresentation.systemImage
                    )
                }
                .accessibilityIdentifier("settings-sync-entry")
            }

            Section("隐私") {
                NavigationLink {
                    PrivacySettingsView(
                        profile: profile,
                        avatarPhoto: avatarPhoto,
                        releaseConfiguration: releaseConfiguration,
                        showsConfigurationDiagnostics: exposesFutureArchitecture
                    )
                } label: {
                    SettingsDestinationLabel(
                        title: "隐私",
                        subtitle: profile.map { "个人主页：\($0.visibility.title)" } ?? "登录后管理资料可见范围",
                        systemImage: "hand.raised"
                    )
                }
                .accessibilityIdentifier("settings-privacy-entry")
            }

            Section("权限") {
                NavigationLink {
                    PermissionsSettingsView(permissionOverride: permissionOverride)
                } label: {
                    SettingsDestinationLabel(
                        title: "权限",
                        subtitle: "定位与照片",
                        systemImage: "checkmark.shield"
                    )
                }
                .accessibilityIdentifier("settings-permissions-entry")
            }

            Section("存储") {
                NavigationLink {
                    StorageSettingsView(snapshotOverride: storageOverride)
                } label: {
                    SettingsDestinationLabel(
                        title: "存储",
                        subtitle: storageOverride.map {
                            SettingsStorageSnapshot.formatted($0.totalPhotoBytes)
                        } ?? "本地照片空间",
                        systemImage: "internaldrive"
                    )
                }
                .accessibilityIdentifier("settings-storage-entry")
            }

            Section("Premium") {
                NavigationLink {
                    PremiumSettingsView(membershipStatusOverride: membershipStatusOverride)
                } label: {
                    SettingsDestinationLabel(
                        title: "Taste Map Premium",
                        subtitle: membershipStatus.settingsTitle,
                        systemImage: "checkmark.seal"
                    )
                }
                .accessibilityIdentifier("settings-premium-entry")
            }

            Section("帮助") {
                NavigationLink {
                    HelpSettingsView(
                        supportURL: releaseConfiguration.legalLinks.supportURL,
                        showsConfigurationDiagnostics: exposesFutureArchitecture
                    )
                } label: {
                    SettingsDestinationLabel(
                        title: "帮助",
                        subtitle: "备份、同步与常见问题",
                        systemImage: "questionmark.circle"
                    )
                }
                .accessibilityIdentifier("settings-help-entry")
            }

            Section("关于") {
                NavigationLink {
                    AboutSettingsView(
                        releaseConfiguration: releaseConfiguration,
                        showsConfigurationDiagnostics: exposesFutureArchitecture
                    )
                } label: {
                    SettingsDestinationLabel(
                        title: "关于 Taste Map",
                        subtitle: "版本与法律信息",
                        systemImage: "info.circle"
                    )
                }
                .accessibilityIdentifier("settings-about-entry")
            }

#if DEBUG
            if exposesFutureArchitecture {
                Section {
                    FutureSettingsRow(title: "恢复我的备份", state: availability.state(for: .restoreBackup))
                    FutureSettingsRow(
                        title: "迁移旧版 Web 数据",
                        state: availability.state(for: .migrateLegacyWebData)
                    )
                    FutureSettingsRow(title: "删除账户", state: availability.state(for: .deleteAccount))
                } header: {
                    Text("未来数据能力 · Development Preview")
                } footer: {
                    Text("这些 route 只用于确认未来信息架构；正式 Settings 不显示，也没有可执行按钮。")
                }
            }
#endif
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(TasteMapCoreTheme.page)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
        .tasteMapBottomNavigationHidden()
        .accessibilityIdentifier("settings-root")
    }

}

struct AccountSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let authenticatedUser: AuthenticatedUserV1?
    let profile: UserProfile?
    let avatarPhoto: PhotoAsset?
    let logoutAction: SettingsLogoutAction
    let accountDeletedAction: SettingsAccountDeletedAction
    @State private var isEditingProfile = false
    @State private var isConfirmingLogout = false
    @State private var isLoggingOut = false
    @State private var message: String?
    @State private var didCopyID = false

    var body: some View {
        List {
            Section("登录状态") {
                LabeledContent("Taste Map", value: authenticatedUser == nil ? "未登录" : "已登录")
                if let userID = authenticatedUser?.id {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Taste Map ID")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Text(userID)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                                .accessibilityIdentifier("settings-tastemap-user-id")
                            Spacer()
                            Button {
                                UIPasteboard.general.string = userID
                                didCopyID = true
                            } label: {
                                Image(systemName: didCopyID ? "checkmark" : "doc.on.doc")
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(didCopyID ? "Taste Map ID 已复制" : "复制 Taste Map ID")
                            .accessibilityIdentifier("settings-copy-user-id")
                        }
                    }
                    Text("这是 Taste Map 自己的账户 ID，不是 Apple 登录标识或邮箱。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let profile {
                Section("个人资料") {
                    Button {
                        isEditingProfile = true
                    } label: {
                        Label("编辑资料", systemImage: "person.crop.circle.badge.pencil")
                    }
                    .accessibilityIdentifier("settings-edit-profile")
                    LabeledContent("显示名称", value: profile.displayName)
                    LabeledContent("主页可见范围", value: profile.visibility.title)
                }
            }

            if authenticatedUser != nil {
                Section {
                    Button("退出登录", role: .destructive) {
                        isConfirmingLogout = true
                    }
                    .disabled(isLoggingOut)
                    .accessibilityIdentifier("settings-sign-out")
                } footer: {
                    Text("退出会撤销当前会话并清理此设备上的 Keychain 凭据，不会删除你的餐厅或到访记录。")
                }
            }

            if let userID = authenticatedUser?.id {
                Section {
                    NavigationLink {
                        AccountDeletionView(
                            currentUserID: userID,
                            completionAction: accountDeletedAction
                        )
                    } label: {
                        Label("删除账户", systemImage: "person.crop.circle.badge.minus")
                            .foregroundStyle(.red)
                    }
                    .accessibilityIdentifier("settings-delete-account")
                } footer: {
                    Text("永久删除 Taste Map 账户需要重新使用 Apple 登录验证，并由服务器完成 D1 与照片对象删除。")
                }
            }

            if isLoggingOut {
                Section { ProgressView("正在退出…") }
            }
            if let message {
                Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TasteMapCoreTheme.page)
        .navigationTitle("账户")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isEditingProfile) {
            if let profile {
                ProfileEditorSheet(profile: profile, avatarPhoto: avatarPhoto)
            }
        }
        .alert("退出 Taste Map？", isPresented: $isConfirmingLogout) {
            Button("退出登录", role: .destructive) {
                Task { await performLogout() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("本地记录会继续保留在此设备。")
        }
    }

    @MainActor
    private func performLogout() async {
        isLoggingOut = true
        message = await logoutAction.perform()
        isLoggingOut = false
        dismiss()
    }
}

struct SettingsLogoutAction: Sendable {
    let perform: @MainActor @Sendable () async -> String
}

struct DataBackupSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NativeAuthServices.self) private var authServices
    let isAuthenticated: Bool
    let currentTasteMapUserID: String?
    let allowsImport: Bool
    @State private var isShowingConfirmation = false
    @State private var isExporting = false
    @State private var exportTask: Task<Void, Never>?
    @State private var artifact: BackupExportArtifact?
    @State private var message: String?

    var body: some View {
        List {
            Section {
                if isExporting {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("正在生成 Backup v1…")
                        Spacer()
                        Button("取消", role: .cancel) { exportTask?.cancel() }
                    }
                    .accessibilityIdentifier("settings-backup-export-progress")
                } else {
                    Button {
                        isShowingConfirmation = true
                    } label: {
                        HStack {
                            Label("导出备份", systemImage: "square.and.arrow.up")
                            Spacer()
                            Text("JSON").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44)
                    }
                    .disabled(!isAuthenticated)
                    .accessibilityIdentifier("settings-backup-export-button")
                }
            } header: {
                Text("Export Backup")
            } footer: {
                Text(isAuthenticated
                    ? "导出当前账户的本地业务数据。文件由你选择保存或分享的位置。"
                    : "登录 Taste Map 后才能导出当前账户的备份。")
            }

            Section("Backup v1 范围") {
                Label("包含餐厅、到访、备注、消费、饭搭子与推荐来源", systemImage: "checkmark.circle")
                Label("不包含照片原图", systemImage: "photo.badge.exclamationmark")
                    .accessibilityIdentifier("settings-backup-photo-exclusion")
            }

            if allowsImport {
                Section {
                    NavigationLink {
                        BackupImportPreflightView(
                            modelContainer: modelContext.container,
                            currentTasteMapUserID: currentTasteMapUserID,
                            fixtureInput: importFixtureInput,
                            injectedFailurePoint: importFailurePoint
                        )
                    } label: {
                        HStack {
                            Label("导入数据", systemImage: "doc.badge.plus")
                            Spacer()
                            Text("JSON")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44)
                    }
                    .disabled(!isAuthenticated)
                    .accessibilityIdentifier("settings-import-data-entry")
                } header: {
                    Text("Import Data")
                } footer: {
                    Text(isAuthenticated
                        ? "安全合并 Backup v1 或 Legacy Web v4 数据；照片原图无法从 JSON 恢复。"
                        : "登录 Taste Map 后才能把数据导入当前账户。")
                }
            }

            if let message {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(message.hasPrefix("失败") ? .red : .secondary)
                        .accessibilityIdentifier("settings-backup-export-message")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TasteMapCoreTheme.page)
        .navigationTitle("数据与备份")
        .navigationBarTitleDisplayMode(.inline)
        .alert("导出 Backup v1", isPresented: $isShowingConfirmation) {
            Button("生成并分享") { startExport() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("备份包含你的餐厅、到访记录、备注、消费、饭搭子和推荐来源等私人数据。Backup v1 不包含照片原图。")
        }
        .sheet(item: $artifact, onDismiss: cleanupPresentedArtifact) { artifact in
            BackupExportShareSheet(fileURL: artifact.fileURL) { completed, error in
                finishSharing(artifact, completed: completed, error: error)
            }
        }
        .onDisappear { exportTask?.cancel() }
    }

    @MainActor
    private func startExport() {
        guard !isExporting, isAuthenticated else { return }
        isExporting = true
        message = nil
        exportTask = Task { @MainActor in
            defer {
                isExporting = false
                exportTask = nil
            }
            do {
                let service = try BackupExportService(context: modelContext)
                artifact = try await service.export(authSessionManager: authServices.sessionManager)
            } catch is CancellationError {
                message = "已取消导出，未保留临时备份文件。"
            } catch {
                message = "失败：\(error.localizedDescription)"
            }
        }
    }

    @MainActor
    private func finishSharing(_ artifact: BackupExportArtifact, completed: Bool, error: Error?) {
        cleanup(artifact)
        self.artifact = nil
        if let error {
            message = "失败：分享未完成（\(error.localizedDescription)）"
        } else if completed {
            message = "Backup v1 已交给你选择的保存或分享位置。"
        } else {
            message = "已取消分享，临时备份文件已清理。"
        }
    }

    @MainActor
    private func cleanupPresentedArtifact() {
        guard let artifact else { return }
        cleanup(artifact)
        self.artifact = nil
    }

    @MainActor
    private func cleanup(_ artifact: BackupExportArtifact) {
        guard let service = try? BackupExportService(context: modelContext) else { return }
        try? service.removeTemporaryExport(artifact)
    }

    private var importFixtureInput: BackupImportFixtureInput? {
#if DEBUG
        BackupImportDevelopmentFixture.current?.input
#else
        nil
#endif
    }

    private var importFailurePoint: BackupImportFailurePoint? {
#if DEBUG
        BackupImportDevelopmentFixture.current?.injectedFailurePoint
#else
        nil
#endif
    }
}

struct SyncSettingsView: View {
    @Environment(SyncCoordinator.self) private var syncCoordinator
    let presentationOverride: SyncPresentation?

    private var presentation: SyncPresentation {
        presentationOverride ?? syncCoordinator.presentation
    }

    var body: some View {
        List {
            Section("当前状态") {
                SyncStatusView(presentation: presentation)
                    .padding(.vertical, 6)
                LabeledContent("待同步记录", value: "\(presentation.pendingCount)")
                    .accessibilityIdentifier("settings-sync-pending-count")
                LabeledContent("待上传照片", value: "\(presentation.pendingPhotoCount)")
                    .accessibilityIdentifier("settings-sync-photo-count")
                if presentation.failedPhotoCount > 0 {
                    LabeledContent("上传失败照片", value: "\(presentation.failedPhotoCount)")
                }
                if presentation.conflictCount > 0 {
                    LabeledContent("同步冲突", value: "\(presentation.conflictCount)")
                }
                LabeledContent(
                    "最近成功同步",
                    value: presentation.lastSyncedAt?.formatted(date: .abbreviated, time: .shortened) ?? "暂无"
                )
#if DEBUG
                if let diagnostic = presentation.diagnostic {
                    LabeledContent("失败阶段", value: diagnostic.stage.rawValue)
                    LabeledContent("请求类别", value: diagnostic.requestCategory)
                    LabeledContent("失败类别", value: diagnostic.category.rawValue)
                    if let httpStatus = diagnostic.httpStatus {
                        LabeledContent("HTTP 状态", value: "\(httpStatus)")
                    }
                    LabeledContent("耗时", value: "\(diagnostic.durationMilliseconds) ms")
                    LabeledContent("重试次数", value: "\(diagnostic.retryCount)")
                }
#endif
            }

            if presentationOverride == nil {
                Section {
                    Button(presentation.allowsRetry ? "重试同步" : "立即同步") {
                        Task {
                            if presentation.allowsRetry {
                                await syncCoordinator.retryNow()
                            } else {
                                await syncCoordinator.synchronizeNow()
                            }
                        }
                    }
                    .disabled(presentation.phase == .syncing || presentation.phase == .signedOut)
                    .accessibilityIdentifier("settings-sync-action")
                } footer: {
                    Text("记录会先保存在本机；联网后将由现有同步队列继续上传。")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TasteMapCoreTheme.page)
        .navigationTitle("同步")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings-sync-page")
    }
}

struct PrivacySettingsView: View {
    let profile: UserProfile?
    let avatarPhoto: PhotoAsset?
    let releaseConfiguration: ReleaseConfiguration
    let showsConfigurationDiagnostics: Bool
    @State private var isEditingProfile = false

    var body: some View {
        List {
            Section {
                if let profile {
                    LabeledContent("当前可见范围", value: profile.visibility.title)
                    Button("修改个人主页可见范围") { isEditingProfile = true }
                        .accessibilityIdentifier("settings-privacy-edit-profile")
                } else {
                    Text("登录后可管理个人主页可见范围。")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("个人主页")
            } footer: {
                Text("这里只管理已经支持的个人主页可见范围，没有新增默认到访或榜单可见范围设置。")
            }

            legalLinks

#if DEBUG
            if showsConfigurationDiagnostics,
               releaseConfiguration.legalLinks.privacyPolicyURL == nil,
               releaseConfiguration.legalLinks.termsOfServiceURL == nil {
                Section("Development Configuration") {
                    Text("Privacy Policy 与 Terms of Service 尚未配置，因此正式用户界面不会显示假链接。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
#endif
        }
        .scrollContentBackground(.hidden)
        .background(TasteMapCoreTheme.page)
        .navigationTitle("隐私")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isEditingProfile) {
            if let profile {
                ProfileEditorSheet(profile: profile, avatarPhoto: avatarPhoto)
            }
        }
    }

    @ViewBuilder
    private var legalLinks: some View {
        if releaseConfiguration.legalLinks.privacyPolicyURL != nil
            || releaseConfiguration.legalLinks.termsOfServiceURL != nil {
            Section("法律信息") {
                if let url = releaseConfiguration.legalLinks.privacyPolicyURL {
                    Link("隐私政策", destination: url)
                }
                if let url = releaseConfiguration.legalLinks.termsOfServiceURL {
                    Link("服务条款", destination: url)
                }
            }
        }
    }
}

struct PremiumSettingsView: View {
    @Environment(PremiumEntitlementService.self) private var entitlementService
    let membershipStatusOverride: MembershipStatus?
    @State private var message: String?

    private var status: MembershipStatus {
        membershipStatusOverride ?? entitlementService.membershipStatus
    }

    var body: some View {
        List {
            Section("会员状态") {
                LabeledContent("当前方案", value: status.settingsTitle)
                if entitlementService.isUsingOfflineCache {
                    Label("显示最近验证的离线会员状态", systemImage: "wifi.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let lastError = entitlementService.lastErrorMessage {
                    Text(lastError).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section {
                Button("查看 Premium 权益") {
                    entitlementService.openPaywall(from: .settings)
                }
                .accessibilityIdentifier("settings-premium-paywall")

                if entitlementService.productsProvider.capabilities.contains(.manageSubscription) {
                    Button("管理订阅") {
                        Task { await manageSubscription() }
                    }
                }
            } footer: {
                if entitlementService.productsProvider.capabilities.isEmpty {
                    Text("当前仅提供权益说明，不显示价格、购买、恢复购买或订阅管理入口。")
                }
            }

            if let message { Section { Text(message).font(.footnote) } }
        }
        .scrollContentBackground(.hidden)
        .background(TasteMapCoreTheme.page)
        .navigationTitle("Premium")
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor
    private func manageSubscription() async {
        do { try await entitlementService.productsProvider.manageSubscription() }
        catch { message = error.localizedDescription }
    }
}

struct SettingsDestinationLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(TasteMapCoreTheme.brand)
                .frame(width: 32, height: 32)
                .background(TasteMapCoreTheme.brandSoft, in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

#if DEBUG
private struct FutureSettingsRow: View {
    let title: String
    let state: SettingsFeatureState

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(state == .developmentOnly ? "架构预留" : "未配置")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif

extension MembershipStatus {
    var settingsTitle: String {
        switch self {
        case .premium: "Premium"
        case .gracePeriod: "Premium · 宽限期"
        case .free: "Free"
        case .expired: "已过期"
        case .loading: "正在确认"
        case .unknown: "尚未确认"
        }
    }
}
