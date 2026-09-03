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
    private let hybridRuntime: TasteMapHybridRuntime
    private let automaticServicesEnabled: Bool

    init() {
        let runtime = TasteMapRuntimeConfiguration.current
        // Backup exports live in their own protected temporary directory. A
        // bounded startup cleanup removes only files created by that subsystem.
        if runtime.allowsAutomaticServices {
            try? BackupExportTemporaryFileStore().cleanup()
        }
        #if DEBUG
        let credentialStore: any AuthCredentialStoring = runtime.isolatesPersistentState
            ? IsolatedAuthCredentialStore()
            : KeychainCredentialStore()
        let networkSession = TasteMapTestRuntimeResources.networkSession(for: runtime)
        let socialOutboxFileURL = runtime.isolatesPersistentState
            ? TasteMapTestRuntimeResources.temporaryRoot(component: "social-outbox")
                .appendingPathComponent("shared-meal-invitations-v1.json")
            : nil
        #else
        let credentialStore: any AuthCredentialStoring = KeychainCredentialStore()
        let networkSession = URLSession.shared
        let socialOutboxFileURL: URL? = nil
        #endif
        let authServices = NativeAuthServices(
            configuration: .current(),
            session: networkSession,
            credentialStore: credentialStore,
            socialOutboxFileURL: socialOutboxFileURL
        )
        // Isolated UI/unit runtimes intentionally have no persisted credential.
        // Resolve that state to the explicit signed-out workspace so fixtures
        // can exercise local mutations without ever reading the real Keychain.
        if runtime.isolatesPersistentState {
            authServices.endLocalAccountSession()
        }
        let container: ModelContainer
        do {
            #if DEBUG
            let useVisualQA = TasteMapUITestFixtures.usesVisualQA
            let useRestaurantDetailFixture = ProcessInfo.processInfo.arguments.contains(
                TasteMapUITestFixtures.detailLaunchArgument
            )
            let useDiscoveryFixture = TasteMapUITestFixtures.usesDiscoveryFixture
            let useCommunityFixture = TasteMapUITestFixtures.usesCommunityFixture
            let useAnalysisFixture = TasteMapUITestFixtures.usesAnalysisFixture
            let useRestaurantAcquisitionFixture = TasteMapUITestFixtures.usesRestaurantAcquisitionFixture
            let useF2ABrowsingFixture = TasteMapUITestFixtures.usesF2ABrowsingFixture
            let useF2BFiltersFixture = TasteMapUITestFixtures.usesF2BFiltersFixture
            let useModule8MapClusterFixture = TasteMapUITestFixtures.usesModule8MapClusterFixture
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
            let useVisualQA = false
            let useRestaurantDetailFixture = false
            let useDiscoveryFixture = false
            let useCommunityFixture = false
            let useAnalysisFixture = false
            let useRestaurantAcquisitionFixture = false
            let useF2ABrowsingFixture = false
            let useF2BFiltersFixture = false
            let useModule8MapClusterFixture = false
            let useOnThisDayFixture = false
            let usePersistentOfflineFixture = false
            let resetPersistentOfflineFixture = false
            let persistenceConfigurationName = "TasteMap"
            let persistenceStorageURL: URL? = nil
            #endif
            container = try TasteMapPersistence.makeContainer(
                inMemory: (runtime.isolatesPersistentState && !usePersistentOfflineFixture)
                    || useRestaurantDetailFixture || useDiscoveryFixture || useCommunityFixture
                    || useAnalysisFixture || useRestaurantAcquisitionFixture || useF2ABrowsingFixture
                    || useF2BFiltersFixture || useModule8MapClusterFixture || useOnThisDayFixture
                    || useVisualQA,
                configurationName: persistenceConfigurationName,
                storageURL: persistenceStorageURL
            )
            #if DEBUG
            if let visualQAMode = TasteMapUITestFixtures.visualQAMode {
                try TasteMapUITestFixtures.insertProfileFixture(into: container)
                try TasteMapVisualQAFixtures.insert(mode: visualQAMode, into: container)
                if TasteMapUITestFixtures.usesAddImageReuseFixture {
                    try TasteMapUITestFixtures.insertAddImageReuseCachedPhotoFixture(into: container)
                }
                authServices.activateVisualQAFixture(userID: TasteMapVisualQAFixtures.userID)
            }
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
            if useModule8MapClusterFixture {
                try TasteMapUITestFixtures.insertProfileFixture(into: container)
                try TasteMapUITestFixtures.insertModule8MapClusterFixture(into: container)
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
        automaticServicesEnabled = runtime.allowsAutomaticServices
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
        if let visualQAMode = TasteMapUITestFixtures.visualQAMode {
            premiumService.activateVisualQAFixture(
                userID: TasteMapVisualQAFixtures.userID,
                override: visualQAMode == .free ? .free : .premium
            )
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
            #if DEBUG
            let photoRootURL: URL?
            if let visualQAMode = TasteMapUITestFixtures.visualQAMode {
                try TasteMapVisualQAFixtures.preparePhotoFiles(mode: visualQAMode)
                photoRootURL = TasteMapVisualQAFixtures.photoRootURL(for: visualQAMode)
            } else {
                photoRootURL = runtime.isolatesPersistentState
                    ? TasteMapTestRuntimeResources.temporaryRoot(component: "photos")
                    : nil
            }
            #else
            let photoRootURL: URL? = nil
            #endif
            photoFiles = try LocalPhotoFileStore(
                rootURL: photoRootURL
            )
        } catch {
            fatalError("Unable to initialize local photo storage: \(error)")
        }
        syncCoordinator = coordinator
        let transferCoordinator = PhotoTransferCoordinator(
            context: container.mainContext,
            api: authServices.photoAPI,
            files: photoFiles,
            sessionManager: authServices.sessionManager,
            syncCoordinator: coordinator,
            networkObserver: NetworkPathObserver()
        )
        photoTransferCoordinator = transferCoordinator
#if DEBUG
        let hybridSearchService: any RestaurantSearching = TasteMapUITestFixtures.hybridRestaurantSearchService
#else
        let hybridSearchService: any RestaurantSearching = MapKitRestaurantSearchService()
#endif
        hybridRuntime = TasteMapHybridRuntime(
            mode: TasteMapHybridRuntimeConfiguration.current,
            container: container,
            authServices: authServices,
            premiumEntitlementService: premiumService,
            syncCoordinator: coordinator,
            photoFiles: photoFiles,
            photoTransferCoordinator: transferCoordinator,
            restaurantSearchService: hybridSearchService
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(automaticServicesEnabled: automaticServicesEnabled)
                .environment(nativeAuthServices)
                .environment(syncCoordinator)
                .environment(premiumEntitlementService)
                .environment(hybridRuntime)
                .environment(\.photoTransferCoordinator, photoTransferCoordinator)
        }
        .modelContainer(modelContainer)
    }
}
