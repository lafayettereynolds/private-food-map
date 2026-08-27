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

    var body: some View {
        RootTabView()
            .task { syncCoordinator.start() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    syncCoordinator.handleAppBecameActive()
                }
            }
    }
}
