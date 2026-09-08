import Foundation
import SwiftData
import Testing
import UIKit
@testable import TasteMap

@MainActor
struct HybridPhase2AIntegrationTests {
    @Test func restaurantHeroSeparatesActualPhotosFromExplicitAvatarAndRefreshesAfterDelete() throws {
        let owner = "tm_content_photo_contract"
        let container = try TasteMapPersistence.makeContainer(inMemory: true, configurationName: "ContentPhotoContract")
        let context = ModelContext(container)
        let restaurant = Restaurant(ownerUserID: owner, name: "真实照片测试餐厅", address: "测试地址",
                                    latitude: 30.2, longitude: 120.1, city: "杭州", status: .visited)
        let visit = Visit(ownerUserID: owner, restaurantId: restaurant.id, visitedAt: .now)
        let marker = PhotoAsset(ownerUserID: owner, restaurantId: restaurant.id, kind: .restaurantMarker,
                                mimeType: "image/jpeg", byteSize: 12)
        let actual = PhotoAsset(ownerUserID: owner, restaurantId: restaurant.id, visitId: visit.id,
                                kind: .visit, mimeType: "image/jpeg", byteSize: 12)
        let foreign = PhotoAsset(ownerUserID: "tm_another_owner", restaurantId: restaurant.id,
                                 kind: .dish, mimeType: "image/jpeg", byteSize: 12)
        context.insert(restaurant); context.insert(visit); context.insert(marker); context.insert(actual); context.insert(foreign)
        try context.save()
        let metadata: [UUID: TasteMapHybridRestaurantMetadata] = [restaurant.id: .init(localUserPhotoID: marker.id, markerType: "image")]
        let service = try TasteMapHybridBridgeService(container: container, ownerUserID: owner, metadataByRestaurantID: metadata)
        let detail = try service.restaurantDetail(id: restaurant.id.uuidString).restaurant
        #expect(detail.image.photoID == marker.id.uuidString.lowercased())
        #expect(detail.contentImage?.photoID == actual.id.uuidString.lowercased())
        #expect(detail.contentImageResolution?.sources.map(\.photoID) == [actual.id.uuidString.lowercased()])
        actual.deletedAt = .now
        try context.save()
        let reopened = try TasteMapHybridBridgeService(container: container, ownerUserID: owner, metadataByRestaurantID: metadata)
            .restaurantDetail(id: restaurant.id.uuidString).restaurant
        #expect(reopened.image.photoID == marker.id.uuidString.lowercased())
        #expect(reopened.contentImage?.kind == .foodCategoryVisual)
        #expect(reopened.contentImageResolution?.sources.isEmpty == true)
    }

    @Test func mapPresentationRejectsDelayedShowAndDelayedHide() {
        var state = TasteMapHybridMapPresentationState()
        state.routeAllowsMap = true
        let show = state.receiveUpdate()
        let hide = state.receiveUpdate()
        let acceptedHide = state.apply(visible: false, revision: hide)
        let acceptedOldShow = state.apply(visible: true, revision: show)
        #expect(acceptedHide)
        #expect(!acceptedOldShow)
        #expect(!state.isVisible)
        let returnToMap = state.receiveUpdate()
        let acceptedReturn = state.apply(visible: true, revision: returnToMap)
        let acceptedOldHide = state.apply(visible: false, revision: hide)
        #expect(acceptedReturn)
        #expect(!acceptedOldHide)
        #expect(state.isVisible)
    }

    @Test func mapPresentationCannotCoverAnotherRouteOrReactModal() {
        var state = TasteMapHybridMapPresentationState()
        for _ in 0..<30 {
            state.routeAllowsMap = false
            let geometryBeforeRoute = state.receiveUpdate()
            state.apply(visible: true, revision: geometryBeforeRoute)
            #expect(!state.isVisible)
            state.routeAllowsMap = true
            #expect(state.isVisible)
            let modal = state.receiveUpdate()
            state.apply(visible: false, revision: modal)
            #expect(!state.isVisible)
            state.routeAllowsMap = false
            state.routeAllowsMap = true
            #expect(!state.isVisible)
        }
    }

    @Test func similarTasteFixtureInteractionsUseTheCommunityVisitNamespace() throws {
        let owner = "tm_hybrid_debug"
        let container = try TasteMapPersistence.makeContainer(inMemory: true, configurationName: "SameTasteCommentIdentity")
        let context = ModelContext(container)
        let restaurant = Restaurant(ownerUserID: owner, name: "评论关联测试餐厅", address: "杭州测试地址", latitude: 30.2, longitude: 120.1, city: "杭州", status: .visited)
        context.insert(restaurant)
        let visit = Visit(ownerUserID: owner, restaurantId: restaurant.id, visitedAt: .now)
        visit.rating = 4.5
        context.insert(visit)
        try context.save()
        let snapshot = try TasteMapHybridBridgeService(container: container, ownerUserID: owner).contentSnapshot()
        let similar = try #require(snapshot.discovery.similarTaste.first?.interaction)
        let activity = try #require(snapshot.community.latest.first?.interaction)
        #expect(similar.visitID.hasPrefix("demo-visit-similar-"))
        #expect(activity.visitID.hasPrefix("demo-visit-"))
        #expect(similar.visitID != activity.visitID)
        #expect(!similar.authorID.isEmpty && !similar.restaurantID.isEmpty)
    }

    @Test func recommendationFixturesExposeDistinctHistoricalReasonsWithoutInventingMissingEvidence() throws {
        let owner = "tm_hybrid_debug"
        let container = try TasteMapPersistence.makeContainer(inMemory: true, configurationName: "RecommendationReasonEvidence")
        let context = ModelContext(container)
        var metadata: [UUID: TasteMapHybridRestaurantMetadata] = [:]
        for index in 0..<3 {
            let restaurant = Restaurant(ownerUserID: owner, name: "日料历史样本\(index)", address: "杭州测试地址", latitude: 30.2, longitude: 120.1, city: "杭州", status: .visited)
            context.insert(restaurant)
            metadata[restaurant.id] = .init(tags: ["日料"])
            for _ in 0..<2 {
                let visit = Visit(ownerUserID: owner, restaurantId: restaurant.id, visitedAt: .now)
                visit.rating = 4.5
                context.insert(visit)
            }
        }
        try context.save()
        let snapshot = try TasteMapHybridBridgeService(container: container, ownerUserID: owner, metadataByRestaurantID: metadata).contentSnapshot()
        let personalized = try #require(snapshot.discovery.forYou.first)
        #expect(personalized.reasons.count == 3)
        #expect(personalized.reasons[1].text == "你过去 2 家日料相关餐厅的平均评分为 9.0/10")
        #expect(personalized.reasons[2].code == "REPEAT_VISIT_PATTERN")
        let similar = try #require(snapshot.discovery.similarTaste.first)
        #expect(similar.reasons.count == 3)
        #expect(similar.reasons[1].code == "SOURCE_VISIT_RATING")
        #expect(similar.reasons[1].text.contains("9/10"))
    }

    @Test func overlappingReactControlsNeverRevealNativeMap() {
        let overlay = TasteMapHybridMapOverlayView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        overlay.reactControlExclusions = [
            CGRect(x: 140, y: 475, width: 110, height: 44),
            CGRect(x: 14, y: 465, width: 362, height: 58),
            CGRect(x: 0, y: 544, width: 390, height: 56)
        ]
        overlay.layoutSubviews()
        let mask = overlay.layer.mask as? CAShapeLayer
        #expect(mask?.path?.contains(CGPoint(x: 195, y: 495)) == false)
        #expect(mask?.path?.contains(CGPoint(x: 40, y: 495)) == false)
        #expect(mask?.path?.contains(CGPoint(x: 1, y: 599)) == false)
        #expect(mask?.path?.contains(CGPoint(x: 195, y: 400)) == true)
        #expect(!overlay.point(inside: CGPoint(x: 195, y: 495), with: nil))

        overlay.reactControlExclusions = []
        overlay.layoutSubviews()
        #expect((overlay.layer.mask as? CAShapeLayer)?.path?.contains(CGPoint(x: 195, y: 495)) == true)
        #expect(overlay.point(inside: CGPoint(x: 195, y: 495), with: nil))
    }

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
        let accountSettings = try TasteMapHybridRouteDTO(surface: .accountSettings)
        let dataBackup = try TasteMapHybridRouteDTO(surface: .dataBackup)
        let dataClear = try TasteMapHybridRouteDTO(surface: .dataClear)
        let privacySettings = try TasteMapHybridRouteDTO(surface: .privacySettings)
        let permissions = try TasteMapHybridRouteDTO(surface: .permissions)
        let storage = try TasteMapHybridRouteDTO(surface: .storage)
        let helpSettings = try TasteMapHybridRouteDTO(surface: .helpSettings)
        let aboutSettings = try TasteMapHybridRouteDTO(surface: .aboutSettings)
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
        #expect(accountSettings.owner == .native)
        #expect(dataBackup.owner == .native)
        #expect(dataClear.owner == .native)
        #expect(privacySettings.owner == .native)
        #expect(permissions.owner == .native)
        #expect(storage.owner == .native)
        #expect(helpSettings.owner == .native)
        #expect(aboutSettings.owner == .native)
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
        #expect(coordinator.back().route.surface == .map)
        #expect(try coordinator.openHybrid(restaurant).route.surface == .restaurant)
        #expect(try coordinator.openHybrid(visitEdit).route.surface == .visitEdit)
        #expect(coordinator.back().route.surface == .restaurant)
        #expect(throws: TasteMapHybridRouteError.unsupportedRoute) {
            try coordinator.openNative(restaurant)
        }
    }

    @Test func cancelledRestaurantDeletionClosesOnlyTheNativeSheet() throws {
        let coordinator = TasteMapHybridNavigationCoordinator()
        let profile = try TasteMapHybridRouteDTO(surface: .profile)
        let detail = try TasteMapHybridRouteDTO(surface: .restaurant, identifier: "provider:place")
        _ = try coordinator.openHybrid(profile)
        _ = try coordinator.openHybrid(detail)
        var events: [TasteMapHybridNavigationStateDTO] = []
        coordinator.didChange = { events.append($0) }
        _ = try coordinator.openNative(TasteMapHybridRouteDTO(surface: .restaurantDelete, identifier: "owned-local-id"))
        #expect(events.last?.route.surface == .restaurantDelete)
        coordinator.dismissNativePresentation()
        #expect(coordinator.current.route == detail)
        #expect(events.allSatisfy { $0.completedAction == nil })
        // A late/duplicate callback after cancellation cannot consume Detail.
        let count = events.count
        #expect(coordinator.completeRestaurantDeletion().route == detail)
        #expect(events.count == count)
        #expect(coordinator.back().route == profile)
    }

    @Test func successfulRestaurantDeletionIsOneAtomicNativeTransitionInEitherNotificationOrder() throws {
        for notificationFirst in [true, false] {
            let coordinator = TasteMapHybridNavigationCoordinator()
            let profile = try TasteMapHybridRouteDTO(surface: .profile)
            let detail = try TasteMapHybridRouteDTO(surface: .restaurant, identifier: "provider:place")
            _ = try coordinator.openHybrid(profile)
            _ = try coordinator.openHybrid(detail)
            _ = try coordinator.openNative(TasteMapHybridRouteDTO(surface: .restaurantDelete, identifier: "owned-local-id"))
            var events: [TasteMapHybridNavigationStateDTO] = []
            var deliveryOrder: [String] = []
            coordinator.didChange = { events.append($0); deliveryOrder.append("completion") }
            // Data notifications invalidate storage projections only; they do
            // not drive Coordinator navigation in either delivery order.
            if notificationFirst { deliveryOrder.append("data") }
            let result = coordinator.completeRestaurantDeletion()
            if !notificationFirst { deliveryOrder.append("data") }
            #expect(deliveryOrder == (notificationFirst ? ["data", "completion"] : ["completion", "data"]))
            #expect(result.route == profile)
            #expect(result.completedAction == .restaurantDelete)
            #expect(result.sourceRequestID == nil)
            #expect(coordinator.presentedNativeRoute == nil)
            #expect(events.count == 1)
            // Mirrors Root's binding: explicit completion already cleared the
            // sheet, so its later dismissal cannot issue a second Back.
            if coordinator.presentedNativeRoute != nil { coordinator.dismissNativePresentation() }
            #expect(coordinator.completeRestaurantDeletion().route == profile)
            #expect(events.count == 1)
            #expect(coordinator.back().route.surface == .map)
        }
    }

    @Test func restaurantDeletionCompletionDoesNotPopAnUnrelatedRouteOrNativeOperation() throws {
        let profile = try TasteMapHybridRouteDTO(surface: .profile)
        let coordinator = TasteMapHybridNavigationCoordinator(initialRoute: profile)
        let deletion = try TasteMapHybridRouteDTO(surface: .restaurantDelete, identifier: "owned-local-id")
        _ = try coordinator.openNative(deletion)
        #expect(coordinator.completeRestaurantDeletion().route == profile)
        #expect(!coordinator.current.canGoBack)
        let edit = try TasteMapHybridRouteDTO(surface: .restaurantEdit, identifier: "owned-local-id")
        _ = try coordinator.openNative(edit)
        #expect(coordinator.completeRestaurantDeletion().route == edit)
        #expect(coordinator.presentedNativeRoute == edit)
        // A new explicit destination invalidates the old Native operation.
        _ = try coordinator.openNative(deletion)
        let other = try TasteMapHybridRouteDTO(surface: .restaurant, identifier: "another-restaurant")
        _ = try coordinator.openHybrid(other)
        #expect(coordinator.completeRestaurantDeletion().route == other)
        #expect(coordinator.back().route == profile)
    }

    @Test func coldRestaurantDeletionFallsBackToMapAndCompletionMetadataIsAdditive() throws {
        let detail = try TasteMapHybridRouteDTO(surface: .restaurant, identifier: "cold-detail")
        let coordinator = TasteMapHybridNavigationCoordinator(initialRoute: detail)
        _ = try coordinator.openNative(TasteMapHybridRouteDTO(surface: .restaurantDelete, identifier: "cold-detail"))
        let completed = coordinator.completeRestaurantDeletion()
        #expect(completed.route.surface == .map)
        #expect(!completed.canGoBack)
        let roundtrip = try JSONDecoder().decode(TasteMapHybridNavigationStateDTO.self, from: JSONEncoder().encode(completed))
        #expect(roundtrip.completedAction == .restaurantDelete)
        let legacy = Data(#"{"route":{"surface":"map"},"owner":"hybrid","canGoBack":false}"#.utf8)
        #expect(try JSONDecoder().decode(TasteMapHybridNavigationStateDTO.self, from: legacy).completedAction == nil)
    }

    @Test func ordinaryColdStartUsesMapButExplicitEntriesAndSessionHistoryWin() throws {
        let cold = TasteMapHybridNavigationCoordinator()
        #expect(cold.current.route.surface == .map)
        #expect(!cold.current.canGoBack)
        let profile = try TasteMapHybridRouteDTO(surface: .profile)
        let explicit = TasteMapHybridNavigationCoordinator(initialRoute: profile)
        #expect(explicit.current.route == profile)
        let detail = try TasteMapHybridRouteDTO(surface: .restaurant, identifier: "deep-linked")
        #expect(TasteMapHybridNavigationCoordinator(initialRoute: detail).current.route == detail)
        _ = try cold.openHybrid(profile)
        #expect(cold.current.route == profile)
        #expect(cold.back().route.surface == .map)
        let share = try TasteMapHybridRouteDTO(surface: .add)
        _ = try cold.handleExternalRoute(share)
        #expect(cold.current.route == share)
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

    @Test func correlatedNavigationKeepsRapidMapAddBackHistoryAndNativeOriginEvents() throws {
        let coordinator = TasteMapHybridNavigationCoordinator()
        var events: [TasteMapHybridNavigationStateDTO] = []
        coordinator.didChange = { events.append($0) }
        let map = try TasteMapHybridRouteDTO(surface: .map)
        let add = try TasteMapHybridRouteDTO(surface: .add)
        let discovery = try TasteMapHybridRouteDTO(surface: .discovery)
        _ = try coordinator.openHybrid(map, sourceRequestID: "request-map-1")
        _ = try coordinator.openHybrid(add, sourceRequestID: "request-add-1")
        #expect(coordinator.back(sourceRequestID: "request-back-1").route == map)
        _ = try coordinator.openHybrid(discovery, sourceRequestID: "request-discovery-1")
        _ = try coordinator.openHybrid(map, sourceRequestID: "request-map-2")
        #expect(coordinator.current.route == map)
        #expect(events.map(\.sourceRequestID) == ["request-map-1", "request-add-1", "request-back-1", "request-discovery-1", "request-map-2"])
        #expect(coordinator.back().route == discovery)
        #expect(events.last?.sourceRequestID == nil)
        let external = try TasteMapHybridDeepLinkParser.route(from: #require(URL(string: "tastemap://restaurant/cold-start")))
        _ = try coordinator.handleExternalRoute(external)
        #expect(coordinator.current.route == external)
        #expect(events.last?.sourceRequestID == nil)
        let native = try TasteMapHybridRouteDTO(surface: .restaurantEdit, identifier: "cold-start")
        _ = try coordinator.openNative(native, sourceRequestID: "request-native-edit")
        coordinator.dismissNativePresentation()
        #expect(events.last?.route == external)
        #expect(events.last?.sourceRequestID == nil)
        _ = try coordinator.handleExternalRoute(add) // Share-extension handoff keeps its original uncorrelated origin.
        #expect(events.last?.route == add)
        #expect(events.last?.sourceRequestID == nil)
        #expect(throws: TasteMapHybridRouteError.unsupportedRoute) { try coordinator.openHybrid(native, sourceRequestID: "wrong-owner") }
        #expect(coordinator.current.route == add)
    }

    @Test func completedRestoredVisitEditorReplacesNativeHistoryAndBackRestoresOrigin() throws {
        let coordinator = TasteMapHybridNavigationCoordinator()
        let detail = try TasteMapHybridRouteDTO(surface: .restaurant, identifier: "restaurant-1")
        let editor = try TasteMapHybridRouteDTO(surface: .visitEdit, identifier: "visit-1")
        _ = try coordinator.openHybrid(detail)
        _ = try coordinator.openHybrid(editor)
        let saved = try coordinator.openHybrid(detail, sourceRequestID: "completed-editor", replaceCurrent: true)
        #expect(saved.route == detail)
        #expect(saved.sourceRequestID == "completed-editor")
        let returned = coordinator.back()
        #expect(returned.route.surface == .map)
        #expect(!returned.canGoBack)
        #expect(coordinator.back().route.surface == .map)
    }

    @Test func replacementKeepsColdRootAndDifferentParentWithoutChangingRouteOwnership() throws {
        let editor = try TasteMapHybridRouteDTO(surface: .visitEdit, identifier: "visit-1")
        let detail = try TasteMapHybridRouteDTO(surface: .restaurant, identifier: "restaurant-1")
        let cold = TasteMapHybridNavigationCoordinator(initialRoute: editor)
        let saved = try cold.openHybrid(detail, replaceCurrent: true)
        #expect(!saved.canGoBack)
        #expect(cold.back().route == detail)
        let coordinator = TasteMapHybridNavigationCoordinator()
        let discovery = try TasteMapHybridRouteDTO(surface: .discovery)
        _ = try coordinator.openHybrid(discovery)
        _ = try coordinator.openHybrid(editor)
        _ = try coordinator.openHybrid(detail, replaceCurrent: true)
        #expect(coordinator.back().route == discovery)
        let native = try TasteMapHybridRouteDTO(surface: .restaurantEdit, identifier: "restaurant-1")
        #expect(throws: TasteMapHybridRouteError.unsupportedRoute) {
            try coordinator.openHybrid(native, replaceCurrent: true)
        }
        #expect(coordinator.current.route == discovery)
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
        let firstVisited = Restaurant(ownerUserID: owner, name: "去过一", address: "A", latitude: 30.2, longitude: 120.1, city: "杭州", status: .visited)
        let secondVisited = Restaurant(ownerUserID: owner, name: "去过二", address: "B", latitude: 30.3, longitude: 120.2, city: "上海", status: .visited)
        context.insert(firstVisited)
        context.insert(secondVisited)
        context.insert(Visit(ownerUserID: owner, restaurantId: firstVisited.id, rating: 4))
        context.insert(Visit(ownerUserID: owner, restaurantId: secondVisited.id, rating: 4.5))
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

    @Test func activeVisitWinsOverStaleAndDuplicateWantToGoRows() throws {
        let owner = "tm_hybrid_visit_status_precedence"
        let container = try TasteMapPersistence.makeContainer(
            inMemory: true,
            configurationName: "HybridVisitStatusPrecedence"
        )
        let context = ModelContext(container)
        context.insert(UserProfile(tasteMapUserID: owner, displayName: "状态测试"))
        let recorded = Restaurant(
            ownerUserID: owner,
            name: "同一家餐厅",
            address: "商场 5 层 501",
            latitude: 30.2500,
            longitude: 120.1600,
            city: "杭州",
            status: .wantToGo
        )
        let duplicateWanted = Restaurant(
            ownerUserID: owner,
            name: "同一家餐厅",
            address: "商场 5 层 501",
            latitude: 30.25005,
            longitude: 120.16005,
            city: "杭州",
            status: .wantToGo
        )
        let unrelatedWanted = Restaurant(
            ownerUserID: owner,
            name: "真正想吃的餐厅",
            address: "另一条路 8 号",
            latitude: 30.30,
            longitude: 120.20,
            city: "杭州",
            status: .wantToGo
        )
        context.insert(recorded)
        context.insert(duplicateWanted)
        context.insert(unrelatedWanted)
        context.insert(Visit(ownerUserID: owner, restaurantId: recorded.id, visitedAt: .now))
        try context.save()

        let service = try TasteMapHybridBridgeService(container: container, ownerUserID: owner)
        let dashboard = try service.profileDashboard()
        #expect(dashboard.restaurants.count == 2)
        #expect(dashboard.restaurants.first { $0.id == recorded.remoteID }?.status == "visited")
        #expect(dashboard.restaurants.first { $0.id == duplicateWanted.remoteID } == nil)
        #expect(dashboard.restaurants.first { $0.id == unrelatedWanted.remoteID }?.status == "wantToGo")

        let wanted = try service.mapViewport(request: .init(
            requestID: "visit-status-wanted-request",
            scope: .wantToGo,
            bounds: nil,
            filters: .init(),
            sort: .recent,
            search: "",
            limit: 300,
            currentLocation: nil
        ))
        #expect(wanted.items.map(\.id) == [unrelatedWanted.remoteID!])
        #expect(wanted.scopeCounts == .init(visited: 1, wantToGo: 1, recommended: 0))

        let verificationContext = ModelContext(container)
        let repaired = try #require(verificationContext.fetch(FetchDescriptor<Restaurant>()).first {
            $0.id == recorded.id
        })
        #expect(repaired.status == .visited)
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
        let quotaObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft))
        var quotaJSON = try #require(quotaObject as? [String: Any])
        quotaJSON["pendingPhotos"] = (0..<3).map { ["photoID": "new-photo-\($0)"] }
        let overLimitDraft = try JSONDecoder().decode(TasteMapHybridVisitWriteDraftDTO.self, from: JSONSerialization.data(withJSONObject: quotaJSON))
        #expect(throws: TasteMapHybridBridgeErrorDTO.self) {
            try service.saveVisit(request: .init(restaurantID: restaurant.remoteID!, visitID: nil, draft: overLimitDraft))
        }
        let beforeSaveVisits = try context.fetch(FetchDescriptor<Visit>())
        #expect(beforeSaveVisits.isEmpty) // Quota rejection must precede the core Visit write.
        #expect(attachedPhotoIDs.isEmpty)
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
        let historicalPhotos = (0..<3).map { index in
            PhotoAsset(ownerUserID: owner, restaurantId: restaurant.id, visitId: visits[0].id,
                       kind: .visit, mimeType: "image/jpeg", byteSize: 10, sortOrder: index)
        }
        historicalPhotos.forEach { context.insert($0) }
        try context.save()
        quotaJSON["pendingPhotos"] = historicalPhotos.map { ["photoID": $0.remoteID!] }
        quotaJSON["note"] = "保留旧三张的无关编辑"
        let retainedDraft = try JSONDecoder().decode(TasteMapHybridVisitWriteDraftDTO.self, from: JSONSerialization.data(withJSONObject: quotaJSON))
        _ = try service.saveVisit(request: .init(restaurantID: restaurant.remoteID!, visitID: saved.visitID, draft: retainedDraft))
        let retainedPhotos = try context.fetch(FetchDescriptor<PhotoAsset>()).filter { $0.visitId == visits[0].id && $0.deletedAt == nil }
        #expect(retainedPhotos.count == 3)
        let retainedVisit = try ModelContext(container).fetch(FetchDescriptor<Visit>()).first { $0.id == visits[0].id }
        #expect(retainedVisit?.note == "保留旧三张的无关编辑")
        #expect(throws: TasteMapHybridBridgeErrorDTO.self) {
            try service.saveVisit(request: .init(restaurantID: restaurant.remoteID!, visitID: saved.visitID, draft: draft))
        }
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
