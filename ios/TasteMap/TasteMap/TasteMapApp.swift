//
//  TasteMapApp.swift
//  TasteMap
//
//  Created by Lafayette on 2026/8/27.
//

import SwiftUI
import SwiftData

@main
struct TasteMapApp: App {
    private let modelContainer: ModelContainer
    private let nativeAuthServices: NativeAuthServices

    init() {
        nativeAuthServices = NativeAuthServices(configuration: .current())
        do {
            #if DEBUG
            let useRestaurantDetailFixture = ProcessInfo.processInfo.arguments.contains(
                TasteMapUITestFixtures.detailLaunchArgument
            )
            #else
            let useRestaurantDetailFixture = false
            #endif
            modelContainer = try TasteMapPersistence.makeContainer(
                inMemory: useRestaurantDetailFixture
            )
            #if DEBUG
            if useRestaurantDetailFixture {
                try TasteMapUITestFixtures.insertRestaurantDetailFixture(into: modelContainer)
            }
            #endif
        } catch {
            fatalError("Unable to initialize local Taste Map storage: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(nativeAuthServices)
        }
        .modelContainer(modelContainer)
    }
}
