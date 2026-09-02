import Foundation
import Testing
@testable import TasteMap

@MainActor
struct HybridPhase2AIntegrationTests {
    @Test func routeValidationAndOwnershipAreCanonical() throws {
        let profile = try TasteMapHybridRouteDTO(surface: .profile)
        let map = try TasteMapHybridRouteDTO(surface: .map)
        let publicProfile = try TasteMapHybridRouteDTO(surface: .profile, identifier: "tm_public")
        let detail = try TasteMapHybridRouteDTO(surface: .restaurant, identifier: "restaurant-1")
        #expect(profile.owner == .hybrid)
        #expect(map.owner == .hybrid)
        #expect(detail.owner == .hybrid)
        #expect(publicProfile.owner == .native)
        #expect(throws: TasteMapHybridRouteError.missingIdentifier) {
            try TasteMapHybridRouteDTO(surface: .restaurant)
        }
    }

    @Test func hybridAndNativeHandoffMaintainOneCurrentOwnerAndBackStack() throws {
        let coordinator = TasteMapHybridNavigationCoordinator()
        let restaurant = try TasteMapHybridRouteDTO(surface: .restaurant, identifier: "restaurant-1")
        let roulette = try TasteMapHybridRouteDTO(surface: .roulette)

        #expect(try coordinator.openHybrid(restaurant).owner == .hybrid)
        #expect(try coordinator.openNative(roulette).owner == .native)
        #expect(coordinator.current.route.surface == .roulette)
        #expect(coordinator.back().route.surface == .restaurant)
        #expect(coordinator.back().route.surface == .profile)
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
}
