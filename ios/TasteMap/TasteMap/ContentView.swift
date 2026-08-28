//
//  ContentView.swift
//  TasteMap
//
//  Created by Lafayette on 2026/8/27.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Environment(NativeAuthServices.self) private var authServices
    @Environment(PremiumEntitlementService.self) private var premiumEntitlementService
    @Environment(\.photoTransferCoordinator) private var photoTransferCoordinator

    var body: some View {
        @Bindable var premiumEntitlementService = premiumEntitlementService
        RootTabView()
            .task {
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
}
