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
        // Device console pipes are otherwise block-buffered in Release.
        setbuf(stdout, nil)
        // Non-sensitive signed-artifact identity for physical-device acceptance.
        let bundle = Bundle.main
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let commit = bundle.object(forInfoDictionaryKey: "TasteMapSourceCommit") as? String ?? "unrecorded"
        let fingerprint = bundle.object(forInfoDictionaryKey: "TasteMapSourceFingerprint") as? String ?? "unrecorded"
        DeviceAcceptanceLog.record("TasteMapBuildIdentity build=\(build) commit=\(commit) source=\(fingerprint) renderer=\(TasteMapHybridRuntimeConfiguration.current.rawValue) referralAvailable=\(ReferralInvitationStore.isAvailable)")
        let runtime = TasteMapRuntimeConfiguration.current
        // Backup exports live in their own protected temporary directory. A
        // bounded startup cleanup removes only files created by that subsystem.
        if runtime.allowsAutomaticServices {
            try? BackupExportTemporaryFileStore().cleanup()
        }
        #if DEBUG
        let photoDeleteQA = PhotoDeleteQASessionFixture.enabled
        let credentialStore: any AuthCredentialStoring
        if photoDeleteQA {
            credentialStore = try! PhotoDeleteQASessionFixture.credentialStore()
        } else if runtime.isolatesPersistentState {
            credentialStore = IsolatedAuthCredentialStore()
        } else {
            credentialStore = KeychainCredentialStore()
        }
        let networkSession = photoDeleteQA ? PhotoDeleteQASessionFixture.session()
            : TasteMapTestRuntimeResources.networkSession(for: runtime)
        let authConfiguration = photoDeleteQA ? try! PhotoDeleteQASessionFixture.configuration() : APIConfiguration.current()
        let appleState: @Sendable (String) async throws -> AppleCredentialStatus = photoDeleteQA
            ? { $0 == PhotoDeleteQATestService.appleIdentifier ? .authorized : .notFound }
            : AppleCredentialStateProvider.state
        let socialOutboxFileURL = runtime.isolatesPersistentState
            ? TasteMapTestRuntimeResources.temporaryRoot(component: "social-outbox")
                .appendingPathComponent("shared-meal-invitations-v1.json")
            : nil
        #else
        let credentialStore: any AuthCredentialStoring = KeychainCredentialStore()
        let networkSession = URLSession.shared
        let photoDeleteQA = false
        let authConfiguration = APIConfiguration.current()
        let appleState = AppleCredentialStateProvider.state
        let socialOutboxFileURL: URL? = nil
        #endif
        let authServices = NativeAuthServices(
            configuration: authConfiguration,
            session: networkSession,
            credentialStore: credentialStore,
            socialOutboxFileURL: socialOutboxFileURL,
            appleState: appleState
        )
        // Isolated UI/unit runtimes intentionally have no persisted credential.
        // Resolve that state to the explicit signed-out workspace so fixtures
        // can exercise local mutations without ever reading the real Keychain.
        if runtime.isolatesPersistentState && !photoDeleteQA {
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
                : (TasteMapAppEnvironment.current == .development ? "TasteMapDevelopment" : "TasteMap")
            let persistenceStorageURL = photoDeleteQA ? try PhotoDeleteQASessionFixture.storageURL() : usePersistentOfflineFixture
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
            let persistenceConfigurationName = TasteMapAppEnvironment.current == .development ? "TasteMapDevelopment" : "TasteMap"
            let persistenceStorageURL: URL? = nil
            #endif
            container = try TasteMapPersistence.makeContainer(
                inMemory: !photoDeleteQA && ((runtime.isolatesPersistentState && !usePersistentOfflineFixture)
                    || useRestaurantDetailFixture || useDiscoveryFixture || useCommunityFixture
                    || useAnalysisFixture || useRestaurantAcquisitionFixture || useF2ABrowsingFixture
                    || useF2BFiltersFixture || useModule8MapClusterFixture || useOnThisDayFixture
                    || useVisualQA),
                configurationName: persistenceConfigurationName,
                storageURL: persistenceStorageURL
            )
            DeviceAcceptanceLog.record("TasteMapDiagnostic category=storage event=container_open name=\(persistenceConfigurationName) apiEnvironment=\(authConfiguration.environment.rawValue)")
            #if DEBUG
            if let visualQAMode = TasteMapUITestFixtures.visualQAMode {
                if try !photoDeleteQA || container.mainContext.fetchCount(FetchDescriptor<Restaurant>()) == 0 {
                    try TasteMapUITestFixtures.insertProfileFixture(into: container)
                    try TasteMapVisualQAFixtures.insert(mode: visualQAMode, into: container)
                }
                if TasteMapUITestFixtures.usesAddImageReuseFixture {
                    try TasteMapUITestFixtures.insertAddImageReuseCachedPhotoFixture(into: container)
                }
                if photoDeleteQA {
                    try PhotoDeleteQASessionFixture.registerPhotos(in: container)
                    // Leave .restoring: the normal session resolver establishes scope.
                } else {
                    authServices.activateVisualQAFixture(userID: TasteMapVisualQAFixtures.userID)
                }
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
        var entitlementAPI: any PremiumEntitlementAPI = authServices.premiumAPI
#if DEBUG
        let trialUIFixture = ProcessInfo.processInfo.environment["TASTEMAP_SIGNUP_TRIAL_UI_TEST"] == "1"
        if trialUIFixture { entitlementAPI = SignupTrialUITestAPI() }
#endif
        #if DEBUG
        let premiumCache: any PremiumEntitlementCaching = runtime.isolatesPersistentState
            ? InMemoryPremiumEntitlementCache()
            : KeychainPremiumEntitlementCache(service: "com.lafayette.tastemap.premium-cache.development")
        #else
        let premiumCache: any PremiumEntitlementCaching = KeychainPremiumEntitlementCache()
        #endif
        let premiumService = PremiumEntitlementService(
            api: entitlementAPI,
            cache: premiumCache,
            purchaseProvider: StoreKitMembershipPurchaseProvider(
                commerceAPI: authServices.premiumCommerceAPI
            ),
            environment: .current
        )
#if DEBUG
        if !trialUIFixture, let override = TasteMapUITestFixtures.premiumOverride {
            _ = premiumService.setDevelopmentOverride(override)
        }
        if !trialUIFixture, let visualQAMode = TasteMapUITestFixtures.visualQAMode {
            premiumService.activateVisualQAFixture(
                userID: TasteMapVisualQAFixtures.userID,
                override: TasteMapUITestFixtures.premiumOverride ?? (visualQAMode == .free ? .free : .premium)
            )
        }
#endif
#if DEBUG
        if trialUIFixture { Task { await premiumService.activate(userID: SignupTrialUITestAPI.owner) } }
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
        let hybridSearchService: any RestaurantSearching = WorldwideRestaurantSearchService()
#endif
        let builtHybridRuntime = TasteMapHybridRuntime(
            mode: TasteMapHybridRuntimeConfiguration.current,
            container: container,
            authServices: authServices,
            premiumEntitlementService: premiumService,
            syncCoordinator: coordinator,
            photoFiles: photoFiles,
            photoTransferCoordinator: transferCoordinator,
            restaurantSearchService: hybridSearchService
        )
        hybridRuntime = builtHybridRuntime
        authServices.credentialInvalidationHandler = { [weak builtHybridRuntime] in
            builtHybridRuntime?.appleCredentialDidInvalidate()
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG
                if PhotoDeleteQASessionFixture.enabled {
                    PhotoDeleteQASessionBootstrap(auth: nativeAuthServices) {
                        ContentView(automaticServicesEnabled: false)
                    }
                } else {
                    ContentView(automaticServicesEnabled: automaticServicesEnabled)
                }
#else
                ContentView(automaticServicesEnabled: automaticServicesEnabled)
#endif
            }
                .environment(nativeAuthServices)
                .environment(syncCoordinator)
                .environment(premiumEntitlementService)
                .environment(hybridRuntime)
                .environment(\.photoTransferCoordinator, photoTransferCoordinator)
        }
        .modelContainer(modelContainer)
    }
}
