import Foundation
import Testing
@testable import TasteMap

@Suite("Taste Map Backup v1 contract")
@MainActor
struct BackupV1ContractTests {
    @Test("Swift decodes the shared full and minimal envelopes")
    func decodesSharedEnvelopes() throws {
        let full = try decode(BackupEnvelopeV1.self, fixture: "backup.v1.full.valid")
        let minimal = try decode(BackupEnvelopeV1.self, fixture: "backup.v1.minimal.valid")

        #expect(full.format == BackupV1Contract.format)
        #expect(full.schemaVersion == BackupV1Contract.schemaVersion)
        #expect(full.scope.includesPhotoBinaries == false)
        #expect(full.entities.restaurants.count == 3)
        #expect(full.entities.visits.first?.myActualSpend?.rawValue == "328.50")
        #expect(minimal.entities.restaurants.isEmpty)
    }

    @Test("Swift decodes every entity golden fixture")
    func decodesEntityFixtures() throws {
        let visit = try decode(BackupVisitV1.self, fixture: "backup.v1.visit.nil-heavy")
        let providerNeutral = try decode(BackupRestaurantV1.self, fixture: "backup.v1.restaurant.provider-neutral")
        let apple = try decode(BackupRestaurantV1.self, fixture: "backup.v1.restaurant.apple-maps")
        let amap = try decode(BackupRestaurantV1.self, fixture: "backup.v1.restaurant.amap")
        let manual = try decode(BackupRestaurantV1.self, fixture: "backup.v1.restaurant.manual")
        let tombstone = try decode(BackupTombstoneV1.self, fixture: "backup.v1.tombstone")
        let photo = try decode(BackupPhotoV1.self, fixture: "backup.v1.photo.metadata-only")
        let companion = try decode(BackupDiningCompanionV1.self, fixture: "backup.v1.companion")
        let source = try decode(BackupRecommendationSourceV1.self, fixture: "backup.v1.recommendation-source")
        let profile = try decode(BackupUserProfileV1.self, fixture: "backup.v1.profile.sanitized")

        #expect(visit.rating == nil)
        #expect(providerNeutral.placeIdentities.count == 2)
        #expect(apple.placeIdentities.first?.provider == .appleMaps)
        #expect(amap.placeIdentities.first?.provider == .amap)
        #expect(manual.placeIdentities.first?.provider == .manual)
        #expect(tombstone.entityType == .restaurant)
        #expect(photo.parent.entityType == .visit)
        #expect(companion.displayName == "小王")
        #expect(source.sourceType == .xiaohongshu)
        #expect(profile.avatarPresetId == .polarBear)
    }

    @Test("Dish and VisitDish stay separate, while List items preserve order")
    func decodesCompoundFixtures() throws {
        struct DishAssociationFixture: Decodable {
            let dish: BackupDishV1
            let visitDish: BackupVisitDishV1
        }
        struct ListFixture: Decodable {
            let list: BackupRestaurantListV1
            let items: [BackupRestaurantListItemV1]
        }

        let association = try decode(DishAssociationFixture.self, fixture: "backup.v1.dish-visit-dish")
        let list = try decode(ListFixture.self, fixture: "backup.v1.list.ordered-items")

        #expect(association.dish.id == association.visitDish.dishId)
        #expect(association.dish.restaurantId == association.visitDish.restaurantId)
        #expect(list.list.id == "list-fixture")
        #expect(list.items.map(\.position) == [0, 1])
    }

    @Test("Nullable Swift DTO fields encode as explicit JSON null")
    func encodesExplicitNulls() throws {
        let visit = try decode(BackupVisitV1.self, fixture: "backup.v1.visit.nil-heavy")
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(visit)) as? [String: Any]
        )

        for key in [
            "partySize", "totalPrice", "myActualSpend", "paymentMode", "pricePerPerson",
            "queueDuration", "diningOccasionText", "rating", "valueRating", "environmentRating",
            "serviceRating", "noiseLevel", "diningDuration", "portionLevel", "transportConvenience",
            "specialNotes", "recommendationSourceId", "recommendationSourceType",
            "recommendationSourceText", "sharedMealReferenceHint", "note",
        ] {
            #expect(object[key] is NSNull, "Expected explicit null for \(key)")
        }
    }

    @Test("Decimal strings, UTC millisecond dates, and half ratings are strict")
    func validatesScalarContracts() throws {
        #expect(BackupMoneyV1(rawValue: "128.50")?.decimalValue == Decimal(string: "128.50"))
        #expect(BackupMoneyV1(rawValue: "128.5") == nil)
        #expect(BackupMoneyV1(rawValue: "128.500") == nil)
        #expect(BackupMoneyV1(rawValue: "-1.00") == nil)
        #expect(BackupTimestampV1(rawValue: "2026-08-29T12:00:00.000Z") != nil)
        #expect(BackupTimestampV1(rawValue: "2026-08-29T20:00:00+08:00") == nil)
        #expect(BackupTimestampV1(rawValue: "2026-08-29T12:00:00Z") == nil)
        #expect(BackupRatingV1(rawValue: 4.5) != nil)
        #expect(BackupRatingV1(rawValue: 4.2) == nil)
    }

    @Test("Swift round-trip preserves Decimal, Date, null, and place identity")
    func roundTripsSharedEnvelope() throws {
        let original = try decode(BackupEnvelopeV1.self, fixture: "backup.v1.full.valid")
        let roundTrip = try JSONDecoder().decode(
            BackupEnvelopeV1.self,
            from: JSONEncoder().encode(original)
        )

        #expect(roundTrip == original)
        #expect(roundTrip.entities.visits[0].myActualSpend?.rawValue == "328.50")
        #expect(roundTrip.entities.visits[0].visitedAt.rawValue == "2026-08-18T11:45:00.000Z")
        #expect(roundTrip.entities.restaurants[1].placeIdentities[0].provider == .appleMaps)
    }

    @Test("Swift canonicalization verifies the cross-language SHA-256 fixture")
    func verifiesSharedIntegrityDigest() throws {
        let envelope = try decode(BackupEnvelopeV1.self, fixture: "backup.v1.full.valid")
        let canonical = try BackupCanonicalJSONV1.canonicalString(for: envelope.integrityPayload)
        let digest = BackupCanonicalJSONV1.sha256Hex(of: canonical)

        #expect(digest == envelope.integrity.digest, "Swift digest: \(digest)")
        #expect(envelope.integrity.canonicalization == BackupV1Contract.canonicalization)
        #expect(envelope.integrity.algorithm == BackupV1Contract.integrityAlgorithm)
    }

    @Test("Swift number spelling matches ECMAScript canonical JSON")
    func canonicalizesNumbersAcrossLanguages() throws {
        let canonical = try BackupCanonicalJSONV1.canonicalString(
            forJSONObject: [-0.0, 0.000001, 0.0000001, 100_000_000_000_000_000_000.0, 1e21]
        )
        #expect(canonical == "[0,0.000001,1e-7,100000000000000000000,1e+21]")
    }

    @Test("Swift rejects a different lineage, schema, scope, or integrity primitive")
    func rejectsInvalidEnvelopeConstants() throws {
        let source = try #require(
            JSONSerialization.jsonObject(with: fixtureData(named: "backup.v1.full.valid"))
                as? [String: Any]
        )

        var wrongFormat = source
        wrongFormat["format"] = "com.example.backup"
        #expect(throws: BackupV1ContractError.invalidFormat) {
            try JSONDecoder().decode(BackupEnvelopeV1.self, from: JSONSerialization.data(withJSONObject: wrongFormat))
        }

        var wrongVersion = source
        wrongVersion["schemaVersion"] = 2
        #expect(throws: BackupV1ContractError.invalidSchemaVersion) {
            try JSONDecoder().decode(BackupEnvelopeV1.self, from: JSONSerialization.data(withJSONObject: wrongVersion))
        }

        var wrongScope = source
        var scope = try #require(wrongScope["scope"] as? [String: Any])
        scope["includesPhotoBinaries"] = true
        wrongScope["scope"] = scope
        #expect(throws: BackupV1ContractError.invalidScope) {
            try JSONDecoder().decode(BackupEnvelopeV1.self, from: JSONSerialization.data(withJSONObject: wrongScope))
        }

        var wrongIntegrity = source
        var integrity = try #require(wrongIntegrity["integrity"] as? [String: Any])
        integrity["algorithm"] = "sha512"
        wrongIntegrity["integrity"] = integrity
        #expect(throws: BackupV1ContractError.invalidIntegrityMetadata) {
            try JSONDecoder().decode(BackupEnvelopeV1.self, from: JSONSerialization.data(withJSONObject: wrongIntegrity))
        }
    }

    @Test("Swift output has no owner, auth, entitlement, sync, provider locator, or local path")
    func encodedDTOsHaveNoSecurityAuthority() throws {
        let envelope = try decode(BackupEnvelopeV1.self, fixture: "backup.v1.full.valid")
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(envelope))
        let keys = collectKeys(object)
        let forbidden = [
            "userId", "ownerUserId", "accessToken", "refreshToken", "appleIdentityToken",
            "appleSub", "authSubject", "oauthSecret", "session", "nonce", "state",
            "membershipTier", "premiumEntitlement", "role", "admin", "storeKitTransactionId",
            "serverVersion", "syncCursor", "syncMutation", "mutationReceipt", "retryState",
            "discoveryRanking", "communityCache", "localPath", "temporaryPath",
            "remoteRecordData", "storageKey", "providerAccountId", "r2Credential",
            "googleOAuthCredential",
        ]

        for key in forbidden {
            #expect(!keys.contains(key), "Forbidden Backup key: \(key)")
        }
    }

    @Test("Legacy Web v4 cannot decode as Backup v1")
    func legacyLineageIsSeparate() throws {
        let legacy = try fixtureData(named: "legacy.web.v4")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(BackupEnvelopeV1.self, from: legacy)
        }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, fixture: String) throws -> Value {
        try JSONDecoder().decode(type, from: fixtureData(named: fixture))
    }

    private func fixtureData(named name: String) throws -> Data {
        let bundle = Bundle(for: BackupContractBundleMarker.self)
        let candidates = [
            bundle.url(forResource: name, withExtension: "json"),
            bundle.url(forResource: name, withExtension: "json", subdirectory: "backup/fixtures"),
            bundle.url(forResource: name, withExtension: "json", subdirectory: "contracts/backup/fixtures"),
        ]
        return try Data(contentsOf: try #require(candidates.compactMap { $0 }.first))
    }

    private func collectKeys(_ value: Any) -> Set<String> {
        if let object = value as? [String: Any] {
            return object.reduce(into: Set(object.keys)) { result, item in
                result.formUnion(collectKeys(item.value))
            }
        }
        if let array = value as? [Any] {
            return array.reduce(into: Set<String>()) { result, item in
                result.formUnion(collectKeys(item))
            }
        }
        return []
    }
}

private final class BackupContractBundleMarker {}
