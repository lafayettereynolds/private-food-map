#if DEBUG
import SwiftData
import SwiftUI

private struct SettingsSyncPreviewHost: View {
    let presentation: SyncPresentation
    private let container: ModelContainer
    private let coordinator: SyncCoordinator

    @MainActor
    init(presentation: SyncPresentation) {
        self.presentation = presentation
        let container = try! TasteMapPersistence.makeContainer(inMemory: true)
        self.container = container
        coordinator = SyncCoordinator(
            context: container.mainContext,
            api: SettingsPreviewSyncAPI(),
            hasAuthenticatedSession: { true }
        )
    }

    var body: some View {
        NavigationStack {
            SyncSettingsView(presentationOverride: presentation)
        }
        .environment(coordinator)
        .modelContainer(container)
    }
}

private struct SettingsPremiumPreviewHost: View {
    let status: MembershipStatus
    private let service: PremiumEntitlementService

    @MainActor
    init(status: MembershipStatus) {
        self.status = status
        service = PremiumEntitlementService.preview(status: status)
    }

    var body: some View {
        NavigationStack {
            PremiumSettingsView(membershipStatusOverride: status)
        }
        .environment(service)
    }
}

private struct SettingsRootPreviewHost: View {
    private let container: ModelContainer
    private let coordinator: SyncCoordinator
    private let premiumService: PremiumEntitlementService

    @MainActor
    init() {
        let container = try! TasteMapPersistence.makeContainer(inMemory: true)
        self.container = container
        coordinator = SyncCoordinator(
            context: container.mainContext,
            api: SettingsPreviewSyncAPI(),
            hasAuthenticatedSession: { false }
        )
        premiumService = PremiumEntitlementService.preview(status: .free)
    }

    var body: some View {
        NavigationStack {
            TasteMapSettingsView(
                authenticatedUser: nil,
                profile: nil,
                avatarPhoto: nil,
                logoutAction: SettingsLogoutAction(perform: { "Preview 未登录" }),
                releaseConfiguration: ReleaseConfiguration(
                    environment: .development,
                    legalLinks: .empty
                ),
                permissionOverride: SettingsPermissionSnapshot(
                    location: .notDetermined,
                    photoAddOnly: .limited
                ),
                storageOverride: .empty,
                syncPresentationOverride: SettingsPreviewFixtures.pending,
                membershipStatusOverride: .free,
                exposesFutureArchitecture: true
            )
        }
        .environment(coordinator)
        .environment(premiumService)
        .modelContainer(container)
    }
}

private struct SettingsPreviewSyncAPI: SyncAPI {
    func push(_ request: SyncPushRequestV1) async throws -> SyncPushResponseV1 {
        throw SettingsPreviewError.unavailable
    }

    func pull(cursor: String, limit: Int) async throws -> SyncPullResponseV1 {
        throw SettingsPreviewError.unavailable
    }
}

private enum SettingsPreviewError: Error { case unavailable }

private enum SettingsPreviewFixtures {
    static let synced = SyncPresentation(
        phase: .synced,
        pendingCount: 0,
        pendingPhotoCount: 0,
        failedPhotoCount: 0,
        conflictCount: 0,
        lastSyncedAt: Date(timeIntervalSince1970: 1_788_000_000)
    )
    static let pending = SyncPresentation(
        phase: .pending,
        pendingCount: 4,
        pendingPhotoCount: 2,
        failedPhotoCount: 0,
        conflictCount: 0,
        lastSyncedAt: Date(timeIntervalSince1970: 1_787_900_000)
    )
    static let failed = SyncPresentation(
        phase: .failed,
        pendingCount: 3,
        pendingPhotoCount: 1,
        failedPhotoCount: 1,
        conflictCount: 0,
        lastSyncedAt: nil
    )
    static let configuredLegal = ReleaseConfiguration(
        environment: .development,
        legalLinks: LegalLinks(
            privacyPolicyURL: URL(string: "https://example.test/privacy")!,
            termsOfServiceURL: URL(string: "https://example.test/terms")!,
            supportURL: URL(string: "https://example.test/support")!
        )
    )
}

#Preview("00 Settings · Development IA") {
    SettingsRootPreviewHost()
}

#Preview("01 Settings · Free user") {
    SettingsPremiumPreviewHost(status: .free)
}

#Preview("02 Settings · Premium user") {
    SettingsPremiumPreviewHost(status: .premium)
}

#Preview("03 Settings · Sync healthy") {
    SettingsSyncPreviewHost(presentation: SettingsPreviewFixtures.synced)
}

#Preview("04 Settings · Sync pending") {
    SettingsSyncPreviewHost(presentation: SettingsPreviewFixtures.pending)
}

#Preview("05 Settings · Sync error") {
    SettingsSyncPreviewHost(presentation: SettingsPreviewFixtures.failed)
}

#Preview("06 Settings · Location denied") {
    NavigationStack {
        PermissionsSettingsView(permissionOverride: SettingsPermissionSnapshot(
            location: .denied,
            photoAddOnly: .allowed
        ))
    }
}

#Preview("07 Settings · Photos limited") {
    NavigationStack {
        PermissionsSettingsView(permissionOverride: SettingsPermissionSnapshot(
            location: .allowed,
            photoAddOnly: .limited
        ))
    }
}

#Preview("08 Settings · Legal configured") {
    NavigationStack {
        AboutSettingsView(
            releaseConfiguration: SettingsPreviewFixtures.configuredLegal,
            showsConfigurationDiagnostics: true,
            appVersion: AppVersionInfo(infoDictionary: [
                "CFBundleDisplayName": "Taste Map",
                "CFBundleShortVersionString": "1.0",
                "CFBundleVersion": "100",
            ])
        )
    }
}

#Preview("09 Settings · Legal missing") {
    NavigationStack {
        AboutSettingsView(
            releaseConfiguration: ReleaseConfiguration(
                environment: .production,
                legalLinks: .empty
            ),
            showsConfigurationDiagnostics: true,
            appVersion: AppVersionInfo(infoDictionary: [:])
        )
    }
}

#Preview("10 Settings · Empty storage") {
    NavigationStack {
        StorageSettingsView(snapshotOverride: .empty)
    }
}

#Preview("11 Settings · Accessibility type") {
    NavigationStack {
        HelpSettingsView(supportURL: nil, showsConfigurationDiagnostics: true)
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
