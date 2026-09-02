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
        XCTAssertEqual(profile.restaurants.count, 5)
        XCTAssertEqual(profile.restaurants.flatMap(\.visits).count, 2)
        XCTAssertEqual(profile.user.id, TasteMapHybridDebugFixture.ownerUserID)
        XCTAssertEqual(profile.user.membershipTier, "member")

        let detail = try service.restaurantDetail(id: "11111111-1111-4111-8111-111111111111")
        XCTAssertEqual(detail.restaurant.name, "湖滨二十八号 · 江南味道")
        XCTAssertEqual(detail.restaurant.image.kind, .providerMerchant)
        XCTAssertTrue(detail.restaurant.image.resourceURL?.hasPrefix("https://") == true)
        XCTAssertEqual(detail.restaurant.visits.count, 2)
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

        let profile = try TasteMapHybridBridgeService(container: container, ownerUserID: owner).profileDashboard()
        XCTAssertEqual(profile.user.nickname, "Owner A")
        XCTAssertEqual(profile.restaurants.map(\.name), ["Owner Restaurant"])
        XCTAssertEqual(profile.followerCount, 0)
        XCTAssertEqual(profile.followingCount, 0)
        XCTAssertNil(try JSONEncoder().encode(profile).range(of: Data("Owner B".utf8)))
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

    func testImageDescriptorNeverExposesAnAbsoluteLocalPath() throws {
        let profile = try makeService().profileDashboard()
        for image in profile.restaurants.map(\.image) {
            XCTAssertFalse(image.resourceURL?.hasPrefix("file://") == true)
            XCTAssertFalse(image.resourceURL?.hasPrefix("/Users/") == true)
            XCTAssertFalse(image.resourceURL?.hasPrefix("/private/") == true)
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
