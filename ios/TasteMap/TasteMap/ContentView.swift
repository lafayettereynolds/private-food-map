//
//  ContentView.swift
//  TasteMap
//
//  Created by Lafayette on 2026/8/27.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Environment(NativeAuthServices.self) private var authServices
    @Environment(PremiumEntitlementService.self) private var premiumEntitlementService
    @Environment(\.photoTransferCoordinator) private var photoTransferCoordinator

    var body: some View {
        @Bindable var premiumEntitlementService = premiumEntitlementService
        RootTabView()
            .tint(TasteMapCoreTheme.brand)
            .task {
                await recoverCompletedAccountDeletionIfNeeded()
                syncCoordinator.start()
                photoTransferCoordinator?.start()
                if let user = await authServices.sessionManager.restoredUser() {
                    await premiumEntitlementService.activate(userID: user.id)
                } else {
                    premiumEntitlementService.sessionDidEnd()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    syncCoordinator.handleAppBecameActive()
                    photoTransferCoordinator?.handleAppBecameActive()
                    if premiumEntitlementService.activeUserID != nil {
                        Task { await premiumEntitlementService.refresh() }
                    }
                }
            }
            .sheet(item: $premiumEntitlementService.presentedSource) { source in
                PremiumPaywallView(source: source)
                    .environment(premiumEntitlementService)
            }
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
            try store.delete()
            premiumEntitlementService.sessionDidEnd()
        } catch {
            // Keep the status credential in Keychain. A later launch can safely
            // retry the local-only completion without resurrecting server data.
        }
    }
}
