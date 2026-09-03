import Foundation
import SwiftData
import XCTest
@testable import TasteMapHybridBridge

@MainActor
final class TasteMapHybridBridgeTests: XCTestCase {
    private func makeService() throws -> TasteMapHybridBridgeService {
#if DEBUG
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/profile-restaurant-rich.json")
        return try TasteMapHybridDebugFixture.makeService(fixtureData: Data(contentsOf: fixtureURL))
#else
        throw XCTSkip("The deterministic fixture is Debug-only.")
#endif
    }

    func testProfileAndRestaurantDTOsComeFromOwnerScopedSwiftData() throws {
        let service = try makeService()
        let profile = try service.profileDashboard()
        XCTAssertEqual(profile.followingCount, 76)
        XCTAssertEqual(profile.followerCount, 128)
        XCTAssertEqual(profile.restaurants.filter { $0.status == "visited" }.count, 90)
        XCTAssertEqual(profile.restaurants.filter { $0.status == "wantToGo" }.count, 25)
        XCTAssertEqual(profile.restaurants.flatMap(\.visits).count, 275)
        XCTAssertEqual(profile.user.id, TasteMapHybridDebugFixture.ownerUserID)
        XCTAssertEqual(profile.user.membershipTier, "member")

        let detail = try service.restaurantDetail(id: "11111111-1111-4111-8111-111111111111")
        XCTAssertEqual(detail.restaurant.name, "湖滨二十八号 · 江南味道")
        XCTAssertEqual(detail.restaurant.image.kind, .foodCategoryVisual)
        XCTAssertNil(detail.restaurant.image.resourceURL)
        XCTAssertNotNil(detail.restaurant.image.categoryVisualID)
        XCTAssertEqual(detail.restaurant.visits.count, 4)
        XCTAssertEqual(detail.editableVisitIDs, detail.restaurant.visits.map(\.id))
        XCTAssertEqual(detail.viewerState, "visited")
        XCTAssertEqual(detail.capabilities, .owned)
    }

    func testOwnerIsolationExcludesForeignRowsAndRelationships() throws {
        let owner = "tm_owner_a"
        let foreignOwner = "tm_owner_b"
        let schema = Schema([Restaurant.self, Visit.self, UserProfile.self, CachedFollow.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(
            "HybridIsolation", schema: schema, isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none
        )])
        let context = ModelContext(container)
        context.insert(UserProfile(tasteMapUserID: owner, displayName: "Owner A"))
        context.insert(UserProfile(tasteMapUserID: foreignOwner, displayName: "Owner B"))
        context.insert(Restaurant(ownerUserID: owner, name: "Owner Restaurant", address: "A", latitude: 0, longitude: 0))
        context.insert(Restaurant(ownerUserID: foreignOwner, name: "Foreign Restaurant", address: "B", latitude: 1, longitude: 1))
        context.insert(CachedFollow(relationshipID: "foreign", currentUserID: foreignOwner, followerUserID: foreignOwner, followedUserID: owner))
        try context.save()

        let service = try TasteMapHybridBridgeService(container: container, ownerUserID: owner)
        let profile = try service.profileDashboard()
        XCTAssertEqual(profile.user.nickname, "Owner A")
        XCTAssertEqual(profile.restaurants.map(\.name), ["Owner Restaurant"])
        XCTAssertEqual(profile.followerCount, 0)
        XCTAssertEqual(profile.followingCount, 0)
        XCTAssertNil(try JSONEncoder().encode(profile).range(of: Data("Owner B".utf8)))
        let detail = try service.restaurantDetail(id: profile.restaurants[0].id)
        XCTAssertEqual(detail.editableVisitIDs, detail.restaurant.visits.map(\.id))
        XCTAssertEqual(detail.viewerState, "visited")
        XCTAssertEqual(detail.capabilities, .owned)
    }

    func testTypedEnvelopeCapabilitiesAndSafeErrorContract() throws {
        let service = try makeService()
        let dispatcher = TasteMapHybridBridgeDispatcher(
            service: service,
            appVersion: "1.0",
            build: "1",
            dataSource: "native-swiftdata-test",
            authState: { TasteMapHybridAuthStateDTO(state: "authenticated", userID: service.ownerUserID, displayName: "Test") }
        )

        let runtime = try response(
            dispatcher,
            method: .runtimeInfo,
            payload: .object([:])
        )
        XCTAssertNil(runtime.error)
        XCTAssertEqual(runtime.version, TasteMapHybridBridgeContract.version)

        let unavailable = try response(
            dispatcher,
            method: .syncRun,
            payload: .object([:])
        )
        XCTAssertEqual(unavailable.error?.code, "capability_unavailable")
        XCTAssertFalse(unavailable.error?.recoverable ?? true)

        let profile = try response(
            dispatcher,
            method: .profileGetCurrent,
            payload: .object([:])
        )
        let encoded = try JSONEncoder().encode(profile)
        for forbidden in ["identityToken", "authorizationCode", "accessToken", "refreshToken", "bearer"] {
            XCTAssertNil(encoded.range(of: Data(forbidden.utf8)))
        }
    }

    func testDiscoveryMutationsAreForwardedThroughAsyncRuntimeBoundary() async throws {
        let service = try makeService()
        var forwarded: [TasteMapHybridBridgeMethod] = []
        let dispatcher = TasteMapHybridBridgeDispatcher(
            service: service,
            appVersion: "1.0",
            build: "1",
            dataSource: "native-swiftdata-test",
            authState: { TasteMapHybridAuthStateDTO(state: "authenticated", userID: service.ownerUserID, displayName: "Test") },
            asynchronousAction: { method, _ in
                forwarded.append(method)
                return .object(["forwarded": .bool(true)])
            }
        )

        for method in [
            TasteMapHybridBridgeMethod.communitySetLike,
            .communityComments,
            .communityAddComment,
            .restaurantSetWantToGo,
        ] {
            let result = await dispatcher.dispatchAsync(TasteMapHybridBridgeRequest(
                version: TasteMapHybridBridgeContract.version,
                requestId: "request-\(method.rawValue)",
                method: method,
                payload: .object([:])
            ))
            XCTAssertNil(result.error, "\(method.rawValue) did not reach the asynchronous runtime")
            guard let value = result.result,
                  case .object(let object) = value,
                  case .bool(true) = object["forwarded"] else {
                XCTFail("\(method.rawValue) returned an unexpected async result")
                continue
            }
        }
        XCTAssertEqual(forwarded, [.communitySetLike, .communityComments, .communityAddComment, .restaurantSetWantToGo])
    }

    func testImageDescriptorNeverExposesAnAbsoluteLocalPath() throws {
        let profile = try makeService().profileDashboard()
        for image in profile.restaurants.map(\.image) {
            XCTAssertFalse(image.resourceURL?.hasPrefix("file://") == true)
            XCTAssertFalse(image.resourceURL?.hasPrefix("/Users/") == true)
            XCTAssertFalse(image.resourceURL?.hasPrefix("/private/") == true)
        }
    }

    func testViewportQueryIsBatchedOwnerScopedAndPreservesRequestIdentity() throws {
        let service = try makeService()
        let request = TasteMapHybridMapBrowseRequest(
            requestID: "viewport-12345678",
            scope: .visited,
            bounds: nil,
            filters: TasteMapHybridMapFilters(
                city: "杭州",
                minimumScoreOutOfTen: nil,
                maximumSpend: nil,
                minimumVisitCount: 1,
                companion: nil,
                cuisine: nil,
                recommendationSource: nil
            ),
            sort: .rating,
            search: "",
            limit: 300,
            currentLocation: nil
        )
        let response = try service.mapViewport(request: request)
        XCTAssertEqual(response.requestID, request.requestID)
        XCTAssertFalse(response.items.isEmpty)
        XCTAssertTrue(response.items.allSatisfy { $0.status == "visited" })
        XCTAssertTrue(response.items.allSatisfy { $0.city == "杭州" })
        XCTAssertTrue(response.items.allSatisfy { $0.visitCount >= 1 })
        XCTAssertTrue(response.items.allSatisfy { !$0.id.isEmpty })
        XCTAssertTrue(response.items.allSatisfy { $0.image.accessibilityLabel.contains($0.name) })

        let recommended = try service.mapViewport(request: TasteMapHybridMapBrowseRequest(
            requestID: "viewport-recommended",
            scope: .recommended,
            bounds: nil,
            filters: TasteMapHybridMapFilters(
                city: nil,
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
        XCTAssertEqual(recommended.items.count, 18)
        XCTAssertEqual(recommended.totalCount, 18)
        XCTAssertEqual(service.projectedRestaurantSnapshotBuildCount, 1)
    }

    func testNativeMapSurfaceUpdateIsTypedAndCarriesNoCredentialOrPersistenceAuthority() throws {
        let marker = TasteMapHybridMapSurfaceMarkerDTO(
            id: "11111111-1111-4111-8111-111111111111",
            name: "湖滨二十八号 · 江南味道",
            latitude: 30.2741,
            longitude: 120.1551,
            status: .visited,
            visitCount: 4,
            averageRating: 4.5,
            fallbackEmoji: "🍣",
            image: TasteMapHybridImageDescriptor(
                kind: .foodDiningFallback,
                stableSeed: "11111111-1111-4111-8111-111111111111",
                accessibilityLabel: "湖滨二十八号 · 江南味道 餐饮图示"
            )
        )
        let request = TasteMapHybridMapSurfaceUpdateRequest(
            requestID: "surface-request-1234",
            visible: true,
            viewportWidth: 402,
            viewportHeight: 874,
            frame: TasteMapHybridMapSurfaceRect(x: 0, y: 168, width: 402, height: 646),
            reactControlExclusions: [TasteMapHybridMapSurfaceRect(x: 135, y: 744, width: 132, height: 44)],
            scope: .visited,
            filters: TasteMapHybridMapFilters(
                city: "杭州", minimumScoreOutOfTen: nil, maximumSpend: nil,
                minimumVisitCount: nil, companion: nil, cuisine: nil, recommendationSource: nil
            ),
            sort: .rating,
            search: "",
            cameraFitKey: "city=杭州",
            selectedRestaurantID: marker.id,
            userAvatarPresetID: "otter",
            userAvatarPhotoID: nil,
            markers: [marker]
        )
        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(TasteMapHybridMapSurfaceUpdateRequest.self, from: encoded)
        XCTAssertEqual(decoded.requestID, request.requestID)
        XCTAssertEqual(decoded.markers.map(\.id), [marker.id])
        XCTAssertEqual(decoded.reactControlExclusions.count, 1)
        XCTAssertEqual(TasteMapHybridBridgeMethod.mapSurfaceUpdate.rawValue, "map.surface.update")
        for forbidden in ["AMap", "securityJsCode", "token", "SwiftData", "mutation"] {
            XCTAssertNil(encoded.range(of: Data(forbidden.utf8)))
        }
    }

    func testContentSnapshotUsesTypedRichDebugContentWithoutSensitiveFields() throws {
        let snapshot = try makeService().contentSnapshot()
        XCTAssertEqual(snapshot.discovery.forYou.count, 12)
        XCTAssertEqual(snapshot.discovery.similarTaste.count, 12)
        XCTAssertEqual(snapshot.discovery.trending.count, 12)
        XCTAssertEqual(snapshot.community.latest.count, 12)
        XCTAssertEqual(snapshot.lists.count, 5)
        XCTAssertTrue(snapshot.discovery.forYou.allSatisfy { !$0.restaurant.name.isEmpty })
        XCTAssertTrue(snapshot.community.latest.contains { $0.visitRating == nil })
        XCTAssertEqual(snapshot.discovery.forYou.first?.viewerState, "none")
        XCTAssertEqual(snapshot.discovery.forYou.dropFirst().first?.viewerState, "want_to_go")
        XCTAssertTrue(snapshot.discovery.forYou.allSatisfy { $0.interaction?.visitID.hasPrefix("demo-visit-") == true })
        XCTAssertTrue(snapshot.community.latest.filter { $0.visitID != nil }.allSatisfy {
            $0.interaction?.activityID == $0.id && $0.interaction?.restaurantID == $0.restaurant.id
        })
        XCTAssertNil(snapshot.community.latest.first { $0.visitID == nil }?.interaction)

        let encoded = try JSONEncoder().encode(snapshot)
        for forbidden in ["accessToken", "refreshToken", "identityToken", "authorizationCode", "file://", "/Users/"] {
            XCTAssertNil(encoded.range(of: Data(forbidden.utf8)))
        }
    }

    private func response(
        _ dispatcher: TasteMapHybridBridgeDispatcher,
        method: TasteMapHybridBridgeMethod,
        payload: TasteMapHybridJSONValue
    ) throws -> TasteMapHybridBridgeResponse {
        let request = TasteMapHybridBridgeRequest(
            version: TasteMapHybridBridgeContract.version,
            requestId: "request-12345678",
            method: method,
            payload: payload
        )
        return dispatcher.dispatch(request)
    }
}
