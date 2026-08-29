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
    private let premiumEntitlementService: PremiumEntitlementService

    init() {
        // Backup exports live in their own protected temporary directory. A
        // bounded startup cleanup removes only files created by that subsystem.
        try? BackupExportTemporaryFileStore().cleanup()
        let authServices = NativeAuthServices(configuration: .current())
        let container: ModelContainer
        do {
            #if DEBUG
            let useRestaurantDetailFixture = ProcessInfo.processInfo.arguments.contains(
                TasteMapUITestFixtures.detailLaunchArgument
            )
            let useDiscoveryFixture = TasteMapUITestFixtures.usesDiscoveryFixture
            let useCommunityFixture = TasteMapUITestFixtures.usesCommunityFixture
            let useAnalysisFixture = TasteMapUITestFixtures.usesAnalysisFixture
            let useRestaurantAcquisitionFixture = TasteMapUITestFixtures.usesRestaurantAcquisitionFixture
            let useF2ABrowsingFixture = TasteMapUITestFixtures.usesF2ABrowsingFixture
            let useF2BFiltersFixture = TasteMapUITestFixtures.usesF2BFiltersFixture
            let useOnThisDayFixture = TasteMapUITestFixtures.usesOnThisDayFixture
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
            let useDiscoveryFixture = false
            let useCommunityFixture = false
            let useAnalysisFixture = false
            let useRestaurantAcquisitionFixture = false
            let useF2ABrowsingFixture = false
            let useF2BFiltersFixture = false
            let useOnThisDayFixture = false
            let usePersistentOfflineFixture = false
            let resetPersistentOfflineFixture = false
            let persistenceConfigurationName = "TasteMap"
            let persistenceStorageURL: URL? = nil
            #endif
            container = try TasteMapPersistence.makeContainer(
                inMemory: useRestaurantDetailFixture || useDiscoveryFixture || useCommunityFixture
                    || useAnalysisFixture || useRestaurantAcquisitionFixture || useF2ABrowsingFixture
                    || useF2BFiltersFixture || useOnThisDayFixture,
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
                try TasteMapUITestFixtures.insertProfileFixture(into: container)
                try TasteMapUITestFixtures.insertRestaurantRouletteFixture(into: container)
            }
            if useDiscoveryFixture {
                try TasteMapUITestFixtures.insertProfileFixture(into: container)
            }
            if useCommunityFixture {
                try TasteMapUITestFixtures.insertProfileFixture(into: container)
            }
            if useAnalysisFixture {
                try TasteMapUITestFixtures.insertProfileFixture(into: container)
                try TasteMapUITestFixtures.insertTasteProfileAnalysisFixture(into: container)
            }
            if useF2ABrowsingFixture {
                try TasteMapUITestFixtures.insertProfileFixture(into: container)
                try TasteMapUITestFixtures.insertF2ABrowsingFixture(into: container)
            }
            if useF2BFiltersFixture {
                try TasteMapUITestFixtures.insertProfileFixture(into: container)
                try TasteMapUITestFixtures.insertF2BFiltersFixture(into: container)
            }
            if useOnThisDayFixture {
                try TasteMapUITestFixtures.insertProfileFixture(into: container)
                try TasteMapUITestFixtures.insertOnThisDayFixture(into: container)
            }
            #endif
        } catch {
            fatalError("Unable to initialize local Taste Map storage: \(error)")
        }
        nativeAuthServices = authServices
        let premiumService = PremiumEntitlementService(
            api: authServices.premiumAPI,
            purchaseProvider: StoreKitMembershipPurchaseProvider(
                commerceAPI: authServices.premiumCommerceAPI
            ),
            environment: .current
        )
#if DEBUG
        if let override = TasteMapUITestFixtures.premiumOverride {
            _ = premiumService.setDevelopmentOverride(override)
        }
#endif
        premiumEntitlementService = premiumService
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
                .environment(premiumEntitlementService)
                .environment(\.photoTransferCoordinator, photoTransferCoordinator)
        }
        .modelContainer(modelContainer)
    }
}
