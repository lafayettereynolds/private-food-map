import Foundation
import SwiftData
import Testing
@testable import TasteMap

@MainActor
struct HybridPhase2AIntegrationTests {
    @Test func routeValidationAndOwnershipAreCanonical() throws {
        let profile = try TasteMapHybridRouteDTO(surface: .profile)
        let map = try TasteMapHybridRouteDTO(surface: .map)
        let publicProfile = try TasteMapHybridRouteDTO(surface: .profile, identifier: "tm_public")
        let detail = try TasteMapHybridRouteDTO(surface: .restaurant, identifier: "restaurant-1")
        let visitEdit = try TasteMapHybridRouteDTO(surface: .visitEdit, identifier: "visit-1")
        let profileEdit = try TasteMapHybridRouteDTO(surface: .profileEdit)
        let restaurantEdit = try TasteMapHybridRouteDTO(surface: .restaurantEdit, identifier: "restaurant-1")
        let restaurantDelete = try TasteMapHybridRouteDTO(surface: .restaurantDelete, identifier: "restaurant-1")
        let restaurantAddToList = try TasteMapHybridRouteDTO(surface: .restaurantAddToList, identifier: "restaurant-1")
        let restaurantWantToGo = try TasteMapHybridRouteDTO(surface: .restaurantWantToGo, identifier: "restaurant-1")
        #expect(profile.owner == .hybrid)
        #expect(map.owner == .hybrid)
        #expect(detail.owner == .hybrid)
        #expect(publicProfile.owner == .native)
        #expect(visitEdit.owner == .native)
        #expect(profileEdit.owner == .native)
        #expect(restaurantEdit.owner == .native)
        #expect(restaurantDelete.owner == .native)
        #expect(restaurantAddToList.owner == .native)
        #expect(restaurantWantToGo.owner == .native)
        #expect(throws: TasteMapHybridRouteError.missingIdentifier) {
            try TasteMapHybridRouteDTO(surface: .restaurant)
        }
        #expect(throws: TasteMapHybridRouteError.missingIdentifier) {
            try TasteMapHybridRouteDTO(surface: .visitEdit)
        }
        #expect(throws: TasteMapHybridRouteError.missingIdentifier) {
            try TasteMapHybridRouteDTO(surface: .restaurantEdit)
        }
        #expect(throws: TasteMapHybridRouteError.missingIdentifier) {
            try TasteMapHybridRouteDTO(surface: .restaurantWantToGo)
        }
    }

    @Test func hybridAndNativeHandoffMaintainOneCurrentOwnerAndBackStack() throws {
        let coordinator = TasteMapHybridNavigationCoordinator()
        let restaurant = try TasteMapHybridRouteDTO(surface: .restaurant, identifier: "restaurant-1")
        let visit = try TasteMapHybridRouteDTO(surface: .visit, identifier: "visit-1")
        let visitEdit = try TasteMapHybridRouteDTO(surface: .visitEdit, identifier: "visit-1")

        #expect(try coordinator.openHybrid(restaurant).owner == .hybrid)
        #expect(try coordinator.openNative(visit).owner == .native)
        #expect(coordinator.current.route.surface == .visit)
        #expect(coordinator.back().route.surface == .restaurant)
        #expect(coordinator.back().route.surface == .profile)
        #expect(try coordinator.openHybrid(restaurant).route.surface == .restaurant)
        #expect(try coordinator.openNative(visitEdit).route.surface == .visitEdit)
        #expect(coordinator.back().route.surface == .restaurant)
        #expect(throws: TasteMapHybridRouteError.unsupportedRoute) {
            try coordinator.openNative(restaurant)
        }
    }

    @Test func deepLinksAreAllowlistedAndTyped() throws {
        #expect(try TasteMapHybridDeepLinkParser.route(from: #require(URL(string: "tastemap://restaurant/r-1"))).surface == .restaurant)
        #expect(try TasteMapHybridDeepLinkParser.route(from: #require(URL(string: "https://tastemap.example/profile/tm_public"))).surface == .profile)
        #expect(try TasteMapHybridDeepLinkParser.route(from: #require(URL(string: "https://tastemap.example/list/list-1"))).surface == .publicList)
        #expect(try TasteMapHybridDeepLinkParser.route(from: #require(URL(string: "https://tastemap.example/activity/a-1"))).surface == .activity)
        #expect(throws: TasteMapHybridRouteError.self) {
            try TasteMapHybridDeepLinkParser.route(from: #require(URL(string: "javascript://restaurant/r-1")))
        }
    }

    @Test func sessionAndEventDTOsContainNoCredentialFields() throws {
        let session = TasteMapHybridAuthStateDTO(state: "authenticated", userID: "tm_a", displayName: "A")
        let payload = try JSONDecoder().decode(
            TasteMapHybridJSONValue.self,
            from: JSONEncoder().encode(session)
        )
        let event = TasteMapHybridEventEnvelope(sequence: 1, name: .authChanged, payload: payload)
        let encoded = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
        #expect(encoded.contains("auth.changed"))
        for forbidden in ["accessToken", "refreshToken", "Authorization", "identityToken", "Keychain"] {
            #expect(!encoded.localizedCaseInsensitiveContains(forbidden))
        }
    }

    @Test func normalizedShareContractCarriesOnlyFingerprintAndSafeHandoffTarget() throws {
        let add = try TasteMapHybridRouteDTO(surface: .add)
        let target = TasteMapHybridNavigationStateDTO(route: add, canGoBack: true)
        let data = try JSONEncoder().encode(target)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("add"))
        #expect(!text.contains("sharedText"))
        #expect(!text.contains("file://"))
    }

    @Test func ownerVisibleCachedRestaurantUsesCanonicalDetailWithoutGrantingEditRights() throws {
        let owner = "tm_hybrid_public_detail"
        let container = try TasteMapPersistence.makeContainer(
            inMemory: true,
            configurationName: "HybridPublicDetail"
        )
        let context = ModelContext(container)
        let projection = DiscoveryRestaurantProjectionV1(
            globalKey: "apple_maps:hybrid-public-restaurant",
            placeIdentities: [
                .init(provider: .appleMaps, externalId: "hybrid-public-restaurant", isPrimary: true),
            ],
            name: "公开可见餐厅",
            address: "湖滨路 1 号",
            city: "杭州",
            latitude: 30.25,
            longitude: 120.16,
            tags: ["江浙菜"],
            pricePerPerson: 128,
            merchantImageUrl: "https://images.example.test/restaurant.jpg",
            markerEmoji: "",
            photo: nil
        )
        context.insert(try CachedDiscoveryRestaurant(
            currentUserID: owner,
            projection: projection,
            fetchedAt: .now
        ))
        try context.save()

        let service = try TasteMapHybridBridgeService(container: container, ownerUserID: owner)
        let publicDetail = try service.restaurantDetail(id: projection.globalKey)
        #expect(publicDetail.restaurant.id == projection.globalKey)
        #expect(publicDetail.restaurant.name == projection.name)
        #expect(publicDetail.viewerState == "none")
        #expect(publicDetail.editableVisitIDs.isEmpty)
        #expect(!publicDetail.capabilities.canEditRestaurant)
        #expect(!publicDetail.capabilities.canDeleteRestaurant)
        #expect(publicDetail.capabilities.canRecordVisit)
        #expect(publicDetail.capabilities.canAddToWantToGo)
        #expect(publicDetail.capabilities.canAddToList)

        _ = try LocalDiscoveryStore(context: context).addToWantToGo(
            projection: projection,
            among: [],
            currentUserID: owner
        )
        let ownedDetail = try service.restaurantDetail(id: projection.globalKey)
        #expect(ownedDetail.viewerState == "want_to_go")
        #expect(ownedDetail.capabilities.canEditRestaurant)
        #expect(ownedDetail.capabilities.canDeleteRestaurant)
    }

    @Test func nativeAcquisitionCandidateCachesOnlyAReadProjectionForCanonicalHybridDetail() throws {
        let owner = "tm_hybrid_acquisition_detail"
        let container = try TasteMapPersistence.makeContainer(
            inMemory: true,
            configurationName: "HybridAcquisitionDetail"
        )
        let context = ModelContext(container)
        let candidate = RestaurantCandidate(
            name: "系统搜索候选餐厅",
            address: "延安路 88 号",
            city: "杭州",
            latitude: 30.26,
            longitude: 120.17,
            placeIdentities: [
                .init(provider: .amap, externalID: "amap-hybrid-acquisition", isPrimary: true),
            ],
            photoURL: URL(string: "https://images.example.test/acquisition.jpg"),
            phone: "0571-12345678",
            openingHours: "11:00-22:00"
        )

        let identifier = try TasteMapHybridRestaurantReferenceResolver.cacheCandidate(
            candidate,
            ownerUserID: owner,
            context: context
        )
        #expect(identifier == "amap:amap-hybrid-acquisition")
        #expect(try context.fetch(FetchDescriptor<Restaurant>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Visit>()).isEmpty)

        let detail = try TasteMapHybridBridgeService(
            container: container,
            ownerUserID: owner
        ).restaurantDetail(id: identifier)
        #expect(detail.restaurant.name == candidate.name)
        #expect(detail.restaurant.address == candidate.address)
        #expect(detail.viewerState == "none")
        #expect(detail.capabilities.canRecordVisit)
        #expect(detail.capabilities.canAddToWantToGo)
        #expect(!detail.capabilities.canEditRestaurant)
        #expect(detail.editableVisitIDs.isEmpty)
    }
}
