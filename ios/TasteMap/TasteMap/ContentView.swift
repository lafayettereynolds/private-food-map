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
    @Environment(\.photoTransferCoordinator) private var photoTransferCoordinator

    var body: some View {
        RootTabView()
            .task {
                syncCoordinator.start()
                photoTransferCoordinator?.start()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    syncCoordinator.handleAppBecameActive()
                    photoTransferCoordinator?.handleAppBecameActive()
                }
            }
    }
}
