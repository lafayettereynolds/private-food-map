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
        let dataBackup = try TasteMapHybridRouteDTO(surface: .dataBackup)
        let permissions = try TasteMapHybridRouteDTO(surface: .permissions)
        let accountDelete = try TasteMapHybridRouteDTO(surface: .accountDelete)
        #expect(profile.owner == .hybrid)
        #expect(map.owner == .hybrid)
        #expect(detail.owner == .hybrid)
        #expect(publicProfile.owner == .native)
        #expect(visitEdit.owner == .hybrid)
        #expect(profileEdit.owner == .native)
        #expect(restaurantEdit.owner == .native)
        #expect(restaurantDelete.owner == .native)
        #expect(restaurantAddToList.owner == .native)
        #expect(restaurantWantToGo.owner == .native)
        #expect(dataBackup.owner == .native)
        #expect(permissions.owner == .native)
        #expect(accountDelete.owner == .native)
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
        let visit = try TasteMapHybridRouteDTO(surface: .visit, identifier: "restaurant-1")
        let visitEdit = try TasteMapHybridRouteDTO(surface: .visitEdit, identifier: "visit-1")

        #expect(try coordinator.openHybrid(restaurant).owner == .hybrid)
        #expect(try coordinator.openHybrid(visit).owner == .hybrid)
        #expect(coordinator.current.route.surface == .visit)
        #expect(coordinator.back().route.surface == .restaurant)
        #expect(coordinator.back().route.surface == .profile)
        #expect(try coordinator.openHybrid(restaurant).route.surface == .restaurant)
        #expect(try coordinator.openHybrid(visitEdit).route.surface == .visitEdit)
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

    @Test func mapScopeCountsRemainOwnerScopedUniqueAndStableAcrossViewportFilters() throws {
        let owner = "tm_hybrid_scope_counts"
        let foreignOwner = "tm_hybrid_scope_counts_foreign"
        let container = try TasteMapPersistence.makeContainer(
            inMemory: true,
            configurationName: "HybridMapScopeCounts"
        )
        let context = ModelContext(container)
        context.insert(Restaurant(ownerUserID: owner, name: "去过一", address: "A", latitude: 30.2, longitude: 120.1, city: "杭州", status: .visited))
        context.insert(Restaurant(ownerUserID: owner, name: "去过二", address: "B", latitude: 30.3, longitude: 120.2, city: "上海", status: .visited))
        context.insert(Restaurant(ownerUserID: owner, name: "想吃一", address: "C", latitude: 30.4, longitude: 120.3, city: "杭州", status: .wantToGo))
        context.insert(Restaurant(ownerUserID: foreignOwner, name: "其他账户", address: "D", latitude: 30.5, longitude: 120.4, city: "杭州", status: .visited))
        try context.save()

        let response = try TasteMapHybridBridgeService(
            container: container,
            ownerUserID: owner
        ).mapViewport(request: .init(
            requestID: "scope-counts-request",
            scope: .visited,
            bounds: .init(north: 30.25, south: 30.15, east: 120.15, west: 120.05),
            filters: .init(
                city: "杭州",
                minimumScoreOutOfTen: nil,
                maximumSpend: nil,
                minimumVisitCount: nil,
                companion: nil,
                cuisine: nil,
                recommendationSource: nil
            ),
            sort: .recent,
            search: "",
            limit: 300,
            currentLocation: nil
        ))

        #expect(response.items.count == 1)
        #expect(response.totalCount == 1)
        #expect(response.scopeCounts == .init(visited: 2, wantToGo: 1, recommended: 0))
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
        context.insert(try CachedDiscoveryPlacement(
            currentUserID: owner,
            city: "杭州",
            trendWindowDays: 7,
            card: DiscoveryCardV1(
                id: "for_you:\(projection.globalKey)",
                mode: .forYou,
                restaurant: projection,
                viewerState: .none,
                ratings: .init(
                    mine: .init(value: nil, sampleCount: 0),
                    community: .init(value: 4.4, sampleCount: 36),
                    friends: .init(value: 4.6, sampleCount: 8),
                    similarTaste: .init(value: 4.5, sampleCount: 12)
                ),
                reasons: [],
                sourceUser: nil,
                activity: nil,
                similarity: nil,
                trend: nil,
                cacheScope: .public,
                rank: 1,
                score: 88
            ),
            generatedAt: .now
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
        #expect(publicDetail.socialStats?.overallUserRating == 8.8)
        #expect(publicDetail.socialStats?.overallUserCount == 36)
        #expect(publicDetail.socialStats?.friendAverageRating == 9.2)
        #expect(publicDetail.socialStats?.friendUserCount == 8)
        #expect(publicDetail.socialStats?.similarTasteAverageRating == 9.0)
        #expect(publicDetail.socialStats?.similarTasteUserCount == 12)

        _ = try LocalDiscoveryStore(context: context).addToWantToGo(
            projection: projection,
            among: [],
            currentUserID: owner
        )
        let ownedDetail = try service.restaurantDetail(id: projection.globalKey)
        #expect(ownedDetail.viewerState == "want_to_go")
        #expect(ownedDetail.capabilities.canEditRestaurant)
        #expect(ownedDetail.capabilities.canDeleteRestaurant)
        #expect(ownedDetail.socialStats == publicDetail.socialStats)
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

        let saved = try TasteMapHybridBridgeService(
            container: container,
            ownerUserID: owner
        ).saveVisit(request: .init(
            restaurantID: identifier,
            visitID: nil,
            draft: TasteMapHybridVisitWriteDraftDTO(
                visitedAt: "2026-09-03T00:00:00.000Z",
                rating: 4,
                visibility: "private",
                diningMode: "dine_in",
                totalPrice: nil,
                myActualSpend: nil,
                paymentMode: nil,
                partySize: 1,
                queueDuration: nil,
                diningOccasions: [],
                diningOccasionText: "",
                valueRating: nil,
                environmentRating: nil,
                serviceRating: nil,
                valueTags: [],
                environmentTags: [],
                serviceTags: [],
                noiseLevel: nil,
                diningDuration: nil,
                portionLevel: nil,
                transportConvenience: nil,
                specialNotes: "",
                recommendationSourceType: nil,
                recommendationSourceUserID: nil,
                recommendationSourceText: "",
                sharedParticipantUserIDs: [],
                companions: [],
                dishes: [],
                pendingPhotos: nil,
                note: "从公开候选记录"
            )
        ))
        let savedRestaurant = try #require(context.fetch(FetchDescriptor<Restaurant>()).first { $0.ownerUserID == owner })
        let savedVisit = try #require(context.fetch(FetchDescriptor<Visit>()).first { $0.ownerUserID == owner })
        #expect(saved.restaurantID == savedRestaurant.remoteID)
        #expect(saved.visitID == savedVisit.remoteID)
        #expect(savedRestaurant.remoteRecordData != nil)
        #expect(savedVisit.note == "从公开候选记录")
    }

    @Test func typedVisitWriteUsesExistingOwnerScopedStoreDishGraphAndMutationQueue() throws {
        let owner = "tm_hybrid_visit_owner"
        let foreignOwner = "tm_hybrid_visit_foreign"
        let container = try TasteMapPersistence.makeContainer(
            inMemory: true,
            configurationName: "HybridVisitWrite"
        )
        let context = ModelContext(container)
        let restaurant = Restaurant(
            ownerUserID: owner,
            name: "写入测试餐厅",
            address: "湖滨路 8 号",
            latitude: 30.25,
            longitude: 120.16,
            city: "杭州"
        )
        let foreign = Restaurant(
            ownerUserID: foreignOwner,
            name: "其他账号餐厅",
            address: "不可写",
            latitude: 31,
            longitude: 121,
            city: "上海"
        )
        context.insert(restaurant)
        context.insert(foreign)
        try context.save()

        var attachedPhotoIDs: [String] = []
        let service = try TasteMapHybridBridgeService(
            container: container,
            ownerUserID: owner,
            attachPendingPhotos: { attachments, _, _, _, _ in
                attachedPhotoIDs = attachments.map(\.photoID)
                return attachments.isEmpty ? 0 : 1
            }
        )
        let draft = TasteMapHybridVisitWriteDraftDTO(
            visitedAt: "2026-09-03T00:00:00.000Z",
            rating: 4.5,
            visibility: "private",
            diningMode: "dine_in",
            totalPrice: 300,
            myActualSpend: 150,
            paymentMode: "aa",
            partySize: 2,
            queueDuration: "under15",
            diningOccasions: ["friends"],
            diningOccasionText: "",
            valueRating: 4.5,
            environmentRating: 4,
            serviceRating: 4,
            valueTags: ["值得"],
            environmentTags: ["安静"],
            serviceTags: ["周到"],
            noiseLevel: "quiet",
            diningDuration: "under120",
            portionLevel: "normal",
            transportConvenience: "convenient",
            specialNotes: "",
            recommendationSourceType: "friend",
            recommendationSourceUserID: nil,
            recommendationSourceText: "朋友",
            sharedParticipantUserIDs: [],
            companions: ["小王"],
            dishes: [TasteMapHybridVisitWriteDishDTO(
                id: UUID().uuidString,
                name: "招牌菜",
                taste: "鲜",
                rating: 4.5,
                price: 88,
                photoID: nil
            )],
            pendingPhotos: [TasteMapHybridPendingPhotoAttachmentDTO(
                photoID: "opaque-pending-photo",
                dishDraftID: nil
            )],
            note: "会再来"
        )
        let saved = try service.saveVisit(request: .init(
            restaurantID: restaurant.remoteID!,
            visitID: nil,
            draft: draft
        ))
        let visits = try context.fetch(FetchDescriptor<Visit>()).filter { $0.ownerUserID == owner && $0.deletedAt == nil }
        let dishes = try context.fetch(FetchDescriptor<Dish>()).filter { $0.ownerUserID == owner && $0.deletedAt == nil }
        let links = try context.fetch(FetchDescriptor<VisitDish>()).filter { $0.ownerUserID == owner && $0.deletedAt == nil }
        let mutations = try context.fetch(FetchDescriptor<SyncMutation>()).filter { $0.ownerUserID == owner }
        #expect(visits.count == 1)
        #expect(dishes.count == 1)
        #expect(links.count == 1)
        #expect(visits[0].note == "会再来")
        #expect(visits[0].companionNames == ["小王"])
        #expect(mutations.contains { $0.entityType == .visit })
        #expect(mutations.contains { $0.entityType == .dish })
        #expect(attachedPhotoIDs == ["opaque-pending-photo"])
        #expect(saved.photoWarning == "到访已保存，但有 1 张照片未能附加。")
        #expect(throws: TasteMapHybridServiceError.restaurantMissing) {
            try service.saveVisit(request: .init(
                restaurantID: foreign.remoteID!,
                visitID: nil,
                draft: draft
            ))
        }

        _ = try service.deleteVisit(id: saved.visitID)
        let verificationContext = ModelContext(container)
        #expect(try verificationContext.fetch(FetchDescriptor<Visit>()).filter { $0.ownerUserID == owner }.isEmpty)
        #expect(try verificationContext.fetch(FetchDescriptor<Visit>()).filter { $0.ownerUserID == foreignOwner }.isEmpty)
    }
}
