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
    private let syncCoordinator: SyncCoordinator
    private let photoTransferCoordinator: PhotoTransferCoordinator

    init() {
        let authServices = NativeAuthServices(configuration: .current())
        let container: ModelContainer
        do {
            #if DEBUG
            let useRestaurantDetailFixture = ProcessInfo.processInfo.arguments.contains(
                TasteMapUITestFixtures.detailLaunchArgument
            )
            let usePersistentOfflineFixture = TasteMapUITestFixtures.usesPersistentFixture
            let resetPersistentOfflineFixture = TasteMapUITestFixtures.requestsPersistentFixtureReset
            let persistenceConfigurationName = usePersistentOfflineFixture
                ? TasteMapUITestFixtures.persistentConfigurationName
                : "TasteMap"
            let persistenceStorageURL = usePersistentOfflineFixture
                ? TasteMapUITestFixtures.persistentStoreURL
                : nil
            #else
            let useRestaurantDetailFixture = false
            let usePersistentOfflineFixture = false
            let resetPersistentOfflineFixture = false
            let persistenceConfigurationName = "TasteMap"
            let persistenceStorageURL: URL? = nil
            #endif
            container = try TasteMapPersistence.makeContainer(
                inMemory: useRestaurantDetailFixture,
                configurationName: persistenceConfigurationName,
                storageURL: persistenceStorageURL
            )
            #if DEBUG
            if useRestaurantDetailFixture {
                try TasteMapUITestFixtures.insertRestaurantDetailFixture(into: container)
            }
            if usePersistentOfflineFixture {
                try TasteMapUITestFixtures.preparePersistentOfflineFixture(
                    in: container,
                    reset: resetPersistentOfflineFixture
                )
                if TasteMapUITestFixtures.requestsPhotoFailureFixture {
                    try TasteMapUITestFixtures.insertPhotoFailureFixture(into: container)
                }
            }
            #endif
        } catch {
            fatalError("Unable to initialize local Taste Map storage: \(error)")
        }
        nativeAuthServices = authServices
        modelContainer = container
        let coordinator = SyncCoordinator(
            context: container.mainContext,
            api: authServices.syncAPI,
            sessionManager: authServices.sessionManager,
            networkObserver: NetworkPathObserver()
        )
        let photoFiles: LocalPhotoFileStore
        do {
            photoFiles = try LocalPhotoFileStore()
        } catch {
            fatalError("Unable to initialize local photo storage: \(error)")
        }
        syncCoordinator = coordinator
        photoTransferCoordinator = PhotoTransferCoordinator(
            context: container.mainContext,
            api: authServices.photoAPI,
            files: photoFiles,
            sessionManager: authServices.sessionManager,
            syncCoordinator: coordinator,
            networkObserver: NetworkPathObserver()
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(nativeAuthServices)
                .environment(syncCoordinator)
                .environment(\.photoTransferCoordinator, photoTransferCoordinator)
        }
        .modelContainer(modelContainer)
    }
}
