import Photos
import SwiftUI
import UIKit

struct PermissionsSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var locationPermission = LocationPermissionManager()
    let permissionOverride: SettingsPermissionSnapshot?
    @State private var snapshot = SettingsPermissionSnapshot(
        location: .notDetermined,
        photoAddOnly: .notDetermined
    )

    var body: some View {
        List {
            Section("定位") {
                permissionRow(
                    title: "使用我的位置",
                    subtitle: locationDescription,
                    state: snapshot.location,
                    identifier: "settings-location-permission"
                )
                if snapshot.location.canOpenSystemSettings {
                    openSettingsButton
                }
            }

            Section("照片") {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "photo.on.rectangle")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("选择照片")
                        Text("Taste Map 使用系统 PhotosPicker；选择单张照片不需要授予整座照片图库的读取权限。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)

                permissionRow(
                    title: "保存分析海报",
                    subtitle: photoDescription,
                    state: snapshot.photoAddOnly,
                    identifier: "settings-photo-permission"
                )
                if snapshot.photoAddOnly.canOpenSystemSettings {
                    openSettingsButton
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TasteMapCoreTheme.page)
        .navigationTitle("权限")
        .navigationBarTitleDisplayMode(.inline)
        .task { refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
    }

    private var locationDescription: String {
        switch snapshot.location {
        case .allowed: "地图可在系统允许时显示你的位置。"
        case .denied, .restricted: "地图仍可使用；如需定位，可前往系统设置调整。"
        case .notDetermined: "Taste Map 会在你使用定位功能时再请求，不会从此页面自动弹窗。"
        case .limited: "地图仅使用系统实际提供的定位范围。"
        }
    }

    private var photoDescription: String {
        switch snapshot.photoAddOnly {
        case .allowed: "已允许 Taste Map 将你生成的分析海报添加到照片。"
        case .limited: "系统当前提供有限照片访问；可在系统设置中调整。"
        case .denied, .restricted: "无法直接保存海报到照片，但仍可使用系统分享。"
        case .notDetermined: "只有你主动保存海报时，Taste Map 才会请求添加照片权限。"
        }
    }

    private func permissionRow(
        title: String,
        subtitle: String,
        state: SettingsPermissionState,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                Spacer()
                Text(state.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor(state))
            }
            Text(subtitle).font(.footnote).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(state.title)。\(subtitle)")
        .accessibilityIdentifier(identifier)
    }

    private var openSettingsButton: some View {
        Button {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        } label: {
            Label("前往系统设置", systemImage: "arrow.up.right.square")
                .frame(minHeight: 44)
        }
        .accessibilityIdentifier("settings-open-system-settings")
    }

    private func statusColor(_ state: SettingsPermissionState) -> Color {
        switch state {
        case .allowed: .green
        case .limited, .notDetermined: .orange
        case .denied, .restricted: .red
        }
    }

    @MainActor
    private func refresh() {
        snapshot = permissionOverride
            ?? SettingsPermissionSnapshot.live(locationStatus: locationPermission.authorizationStatus)
    }
}

struct StorageSettingsView: View {
    let snapshotOverride: SettingsStorageSnapshot?
    @State private var snapshot = SettingsStorageSnapshot.empty
    @State private var errorMessage: String?
    private let inspector = SettingsStorageInspector()

    var body: some View {
        List {
            Section {
                LabeledContent(
                    "照片总空间",
                    value: SettingsStorageSnapshot.formatted(snapshot.totalPhotoBytes)
                )
                LabeledContent(
                    "用户原图",
                    value: SettingsStorageSnapshot.formatted(snapshot.originalPhotoBytes)
                )
                LabeledContent(
                    "显示版本",
                    value: SettingsStorageSnapshot.formatted(snapshot.displayPhotoBytes)
                )
                LabeledContent(
                    "缩略图",
                    value: SettingsStorageSnapshot.formatted(snapshot.thumbnailPhotoBytes)
                )
            } header: {
                Text("本地照片")
            } footer: {
                Text("用户原图可能是设备上的唯一副本；本页只读统计，绝不会把它当作缓存删除。")
            }

            Section {
                Label("分享海报与 Backup 临时文件会自动清理", systemImage: "clock.arrow.circlepath")
                    .accessibilityElement(children: .combine)
            } header: {
                Text("自动管理的临时文件")
            } footer: {
                Text("这些临时文件不属于长期 Storage，也不提供手动删除入口。用户已保存到 Files 的备份不受 Taste Map 管理。")
            }

            if let errorMessage {
                Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TasteMapCoreTheme.page)
        .navigationTitle("存储")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .accessibilityIdentifier("settings-storage-page")
    }

    @MainActor
    private func load() async {
        if let snapshotOverride {
            snapshot = snapshotOverride
            return
        }
        do { snapshot = try await inspector.snapshot() }
        catch { errorMessage = "暂时无法计算本地照片空间。" }
    }
}

struct HelpSettingsView: View {
    let supportURL: URL?
    let showsConfigurationDiagnostics: Bool

    var body: some View {
        List {
            Section("数据与备份") {
                helpRow(
                    "Backup v1 包含什么？",
                    "包含餐厅、到访、备注、消费、饭搭子、推荐来源等本地业务数据。"
                )
                helpRow(
                    "照片会备份吗？",
                    "Backup v1 不包含照片原图，只包含合同允许的安全照片元数据。"
                )
            }
            Section("同步") {
                helpRow(
                    "离线时可以记录吗？",
                    "可以。记录会先保存在本机，联网后由现有同步队列继续上传。"
                )
            }
            Section("餐厅与定位") {
                helpRow(
                    "如何添加餐厅？",
                    "使用底部的“添加餐厅”，可搜索、粘贴分享链接或手动填写。"
                )
                helpRow(
                    "定位被拒绝怎么办？",
                    "地图仍可使用。需要定位时，可在 Settings 的权限页前往系统设置调整。"
                )
            }
            if let supportURL {
                Section("Support") { Link("打开支持页面", destination: supportURL) }
            }
#if DEBUG
            if showsConfigurationDiagnostics, supportURL == nil {
                Section("Development Configuration") {
                    Text("Support URL 尚未配置，正式用户界面不会显示假链接。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
#endif
        }
        .scrollContentBackground(.hidden)
        .background(TasteMapCoreTheme.page)
        .navigationTitle("帮助")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func helpRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

struct AboutSettingsView: View {
    let releaseConfiguration: ReleaseConfiguration
    let showsConfigurationDiagnostics: Bool
    var appVersion = AppVersionInfo()

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text(appVersion.displayName).font(.title3.bold())
                    Text("记录属于你的每一顿")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .accessibilityElement(children: .combine)
            }

            Section("版本") {
                LabeledContent("App Version", value: appVersion.version)
                    .accessibilityIdentifier("settings-app-version")
                LabeledContent("Build", value: appVersion.build)
                    .accessibilityIdentifier("settings-build-number")
            }

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

#if DEBUG
            if showsConfigurationDiagnostics,
               !releaseConfiguration.releaseValidationIssues.isEmpty {
                Section("Development Release Check") {
                    Text("Production legal links 尚未完整配置；Debug 不会因此无法启动。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
#endif
        }
        .scrollContentBackground(.hidden)
        .background(TasteMapCoreTheme.page)
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings-about-page")
    }
}
