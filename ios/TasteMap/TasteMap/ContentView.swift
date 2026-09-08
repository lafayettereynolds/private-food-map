//
//  ContentView.swift
//  TasteMap
//
//  Created by Lafayette on 2026/8/27.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    let automaticServicesEnabled: Bool

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Environment(NativeAuthServices.self) private var authServices
    @Environment(PremiumEntitlementService.self) private var premiumEntitlementService
    @Environment(TasteMapHybridRuntime.self) private var hybridRuntime
    @Environment(\.photoTransferCoordinator) private var photoTransferCoordinator

    init(automaticServicesEnabled: Bool = true) {
        self.automaticServicesEnabled = automaticServicesEnabled
    }

    var body: some View {
        @Bindable var premiumEntitlementService = premiumEntitlementService
        rootView
            // Drop private presentation state on logout/revocation, not data.
            .id(authServices.localAccountScope.authenticatedUserID)
            .tint(TasteMapCoreTheme.brand)
            .environment(\.localAccountScope, authServices.localAccountScope)
            .task {
                guard automaticServicesEnabled else { return }
                await recoverCompletedAccountDeletionIfNeeded()
                let user = await authServices.restoreLocalAccountScope()
                if let user {
                    try? LocalAccountOwnershipMigrator(context: modelContext).activate(userID: user.id)
                }
                syncCoordinator.start()
                photoTransferCoordinator?.start()
                if let user {
                    await premiumEntitlementService.activate(userID: user.id)
                } else {
                    premiumEntitlementService.sessionDidEnd()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if automaticServicesEnabled, newPhase == .active {
                    syncCoordinator.handleAppBecameActive()
                    photoTransferCoordinator?.handleAppBecameActive()
                    if premiumEntitlementService.activeUserID != nil {
                        Task { await premiumEntitlementService.refresh() }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .tasteMapSyncDidComplete)) { _ in
                guard automaticServicesEnabled, premiumEntitlementService.activeUserID != nil else { return }
                // First valid Visit may have qualified a referral on the server.
                Task { await premiumEntitlementService.refresh() }
            }
            .sheet(item: $premiumEntitlementService.presentedSource) { source in
                PremiumPaywallView(source: source)
                    .environment(premiumEntitlementService)
            }
    }

    @ViewBuilder
    private var rootView: some View {
#if DEBUG
        if hybridRuntime.mode == .hybridDevelopment {
            TasteMapHybridDevelopmentRootView()
        } else {
            RootTabView()
        }
#else
        RootTabView()
#endif
    }

    @MainActor
    private func recoverCompletedAccountDeletionIfNeeded() async {
        let store = AccountDeletionCredentialStore()
        let loaded: PendingAccountDeletionCredential?
        do { loaded = try store.load() }
        catch { return }
        guard let pending = loaded else { return }
        guard let job = try? await authServices.releaseSafetyAPI.accountDeletionStatus(
            statusToken: pending.statusToken
        ), job.status == .completed else { return }

        do {
            _ = try await LocalAccountDataPurger(context: modelContext)
                .purgeCurrentAccount(userID: pending.userID)
            try await authServices.sessionManager.clearLocalSessionAfterAccountDeletion()
            authServices.endLocalAccountSession()
            try store.delete()
            premiumEntitlementService.sessionDidEnd()
        } catch {
            // Keep the status credential in Keychain. A later launch can safely
            // retry the local-only completion without resurrecting server data.
        }
    }
}
