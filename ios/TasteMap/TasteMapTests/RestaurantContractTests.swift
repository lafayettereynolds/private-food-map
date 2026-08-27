import Foundation
import Testing
@testable import TasteMap

@Suite("Restaurant shared JSON contract")
struct RestaurantContractTests {
    @Test("Swift decodes the shared Apple Maps fixture")
    func decodesSharedV1Fixture() throws {
        let restaurant = try JSONDecoder().decode(
            RestaurantJSONContractV1.self,
            from: try fixture(named: "restaurant.v1.valid")
        )

        #expect(restaurant.version == 1)
        #expect(restaurant.amapPoiId == nil)
        #expect(restaurant.id != restaurant.placeIdentities[0].externalId)
        #expect(restaurant.placeIdentities[0].provider == .appleMaps)
    }

    @Test("Swift upgrades the shared legacy Web fixture")
    func upgradesSharedLegacyFixture() throws {
        let restaurant = try JSONDecoder().decode(
            RestaurantJSONContractV1.self,
            from: try fixture(named: "restaurant.v0.legacy")
        )

        #expect(restaurant.version == 1)
        #expect(restaurant.amapPoiId == "B0LEGACYPOI")
        #expect(restaurant.placeIdentities == [try RestaurantPlaceIdentityContract(
            provider: .amap,
            externalId: "B0LEGACYPOI",
            isPrimary: true,
            createdAt: restaurant.createdAt,
            updatedAt: restaurant.updatedAt
        )])
    }

    @Test("Required nullable fields cannot be omitted")
    func requiredNullableFieldCannotBeMissing() throws {
        var object = try #require(JSONSerialization.jsonObject(with: fixture(named: "restaurant.v1.valid")) as? [String: Any])
        object.removeValue(forKey: "phone")
        let data = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RestaurantJSONContractV1.self, from: data)
        }
    }

    @Test("Encoding preserves explicit null fields")
    func encodingPreservesRequiredNulls() throws {
        let restaurant = try JSONDecoder().decode(
            RestaurantJSONContractV1.self,
            from: try fixture(named: "restaurant.v1.valid")
        )
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(restaurant)) as? [String: Any])

        #expect(object["phone"] is NSNull)
        #expect(object["deletedAt"] is NSNull)
        #expect(object["amapPoiId"] == nil)
    }

    @Test("API URL configuration stays unset until a real URL is known")
    func apiURLIsEnvironmentSpecificAndOptional() throws {
        let missing = try APIConfiguration.resolve(environment: .production, values: [:])
        #expect(missing.baseURL == nil)
        #expect(throws: APIConfigurationError.missingBaseURL(.production)) {
            try missing.url(for: "/api/sync")
        }

        let configured = try APIConfiguration.resolve(environment: .development, values: [
            APIConfiguration.developmentKey: "http://127.0.0.1:8788/"
        ])
        #expect(try configured.url(for: "/api/sync").absoluteString == "http://127.0.0.1:8788/api/sync")
    }

    private func fixture(named name: String) throws -> Data {
        let bundle = Bundle(for: ContractBundleMarker.self)
        let candidates = [
            bundle.url(forResource: name, withExtension: "json"),
            bundle.url(forResource: name, withExtension: "json", subdirectory: "fixtures"),
            bundle.url(forResource: name, withExtension: "json", subdirectory: "contracts/fixtures")
        ]
        return try Data(contentsOf: try #require(candidates.compactMap { $0 }.first))
    }
}

private final class ContractBundleMarker {}
