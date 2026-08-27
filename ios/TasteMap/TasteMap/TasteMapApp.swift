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

    init() {
        do {
            modelContainer = try TasteMapPersistence.makeContainer()
        } catch {
            fatalError("Unable to initialize local Taste Map storage: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
