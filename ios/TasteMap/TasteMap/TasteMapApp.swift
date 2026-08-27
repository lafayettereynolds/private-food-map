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
            modelContainer = try TasteMapPersistence.makeContainer()
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
