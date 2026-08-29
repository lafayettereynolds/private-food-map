import Foundation
import Testing
@testable import TasteMap

@Suite("Legacy Web v4 strict decoder")
@MainActor
struct LegacyWebBackupV4DecoderTests {
    private let decoder = LegacyWebBackupV4Decoder()

    @Test("Exact v4 lineage and the checked-in empty fixture decode")
    func exactLineageAndSharedFixture() throws {
        let graph = try decoder.decode(fixtureData(named: "legacy.web.v4"))
        #expect(graph.sourceMetadata.sourceLineage == .legacyWebV4)
        #expect(graph.sourceMetadata.app == "Taste Map")
        #expect(graph.sourceMetadata.version == 4)
        #expect(graph.restaurants.isEmpty)
        #expect(graph.conversionReport.sourceLineage == .legacyWebV4)
    }

    @Test("Wrong app, wrong version, and missing lineage fields are rejected")
    func rejectsWrongOrMissingLineage() throws {
        var wrongApp = LegacyFixture.envelope()
        wrongApp["app"] = "Other App"
        #expect(throws: LegacyWebBackupV4DecodeError.invalidApp) {
            try decoder.decode(LegacyFixture.data(wrongApp))
        }

        var wrongVersion = LegacyFixture.envelope()
        wrongVersion["version"] = 3
        #expect(throws: LegacyWebBackupV4DecodeError.invalidVersion) {
            try decoder.decode(LegacyFixture.data(wrongVersion))
        }

        var missingApp = LegacyFixture.envelope()
        missingApp.removeValue(forKey: "app")
        #expect(throws: LegacyWebBackupV4DecodeError.missingApp) {
            try decoder.decode(LegacyFixture.data(missingApp))
        }

        var missingVersion = LegacyFixture.envelope()
        missingVersion.removeValue(forKey: "version")
        #expect(throws: LegacyWebBackupV4DecodeError.missingVersion) {
            try decoder.decode(LegacyFixture.data(missingVersion))
        }
    }

    @Test("Array, primitive, malformed JSON, and Backup v1 do not masquerade as legacy")
    func rejectsNonLegacyDocuments() throws {
        #expect(throws: LegacyWebBackupV4DecodeError.rootMustBeObject) {
            try decoder.decode(LegacyFixture.data([]))
        }
        #expect(throws: LegacyWebBackupV4DecodeError.rootMustBeObject) {
            try decoder.decode(Data("\"Taste Map\"".utf8))
        }
        #expect(throws: LegacyWebBackupV4DecodeError.malformedJSON) {
            try decoder.decode(Data("{".utf8))
        }
        #expect(throws: LegacyWebBackupV4DecodeError.backupV1UsesDifferentLineage) {
            try decoder.decode(LegacyFixture.data([
                "format": "com.tastemap.backup",
                "schemaVersion": 1,
            ]))
        }
    }

    @Test("Required metadata and all nine v4 collections are strict")
    func requiresEnvelopeShape() throws {
        var missingMetadata = LegacyFixture.envelope()
        missingMetadata.removeValue(forKey: "exportedAt")
        #expect(throws: LegacyWebBackupV4DecodeError.missingMetadata("exportedAt")) {
            try decoder.decode(LegacyFixture.data(missingMetadata))
        }

        var invalidDate = LegacyFixture.envelope()
        invalidDate["exportedAt"] = "yesterday"
        #expect(throws: LegacyWebBackupV4DecodeError.invalidMetadata("exportedAt")) {
            try decoder.decode(LegacyFixture.data(invalidDate))
        }

        var missingCollection = LegacyFixture.envelope()
        missingCollection.removeValue(forKey: "photos")
        #expect(throws: LegacyWebBackupV4DecodeError.missingCollection("photos")) {
            try decoder.decode(LegacyFixture.data(missingCollection))
        }

        var invalidCollection = LegacyFixture.envelope()
        invalidCollection["visits"] = [:]
        #expect(throws: LegacyWebBackupV4DecodeError.invalidCollection("visits")) {
            try decoder.decode(LegacyFixture.data(invalidCollection))
        }
    }

    @Test("Restaurant-only and wantToGo provider-neutral records stay distinct")
    func restaurantOnlyAndWantToGo() throws {
        var envelope = LegacyFixture.envelope()
        envelope["restaurants"] = [
            LegacyFixture.restaurant(id: "r-amap", amapPoiID: "amap-100"),
            LegacyFixture.restaurant(id: "r-neutral", status: "wantToGo", amapPoiID: ""),
        ]
        let graph = try decoder.decode(LegacyFixture.data(envelope))

        #expect(graph.restaurants.count == 2)
        #expect(graph.restaurants.first(where: { $0.sourceID == "r-amap" })?.placeIdentities.first?.provider == .amap)
        #expect(graph.restaurants.first(where: { $0.sourceID == "r-neutral" })?.status == .wantToGo)
        #expect(graph.restaurants.first(where: { $0.sourceID == "r-neutral" })?.placeIdentities.isEmpty == true)
        #expect(graph.conversionReport.issues.contains { $0.code == .providerNeutralRestaurant })
    }

    @Test("Existing provider identities win, duplicates collapse, and primary conflicts require review")
    func placeIdentityRules() throws {
        var restaurant = LegacyFixture.restaurant(id: "r1", amapPoiID: "amap-1")
        restaurant["placeIdentities"] = [
            LegacyFixture.identity(provider: "apple_maps", externalID: "apple-1", primary: true),
            LegacyFixture.identity(provider: "apple_maps", externalID: "apple-1", primary: true),
            LegacyFixture.identity(provider: "amap", externalID: "amap-1", primary: true),
        ]
        var envelope = LegacyFixture.envelope()
        envelope["restaurants"] = [restaurant]
        let graph = try decoder.decode(LegacyFixture.data(envelope))

        let staged = try #require(graph.restaurants.first)
        #expect(staged.placeIdentities.count == 2)
        #expect(staged.placeIdentities.contains { $0.provider == .appleMaps && $0.externalID == "apple-1" })
        #expect(graph.conversionReport.issues.contains { $0.code == .duplicateProviderIdentityRemoved })
        #expect(graph.conversionReport.issues.contains {
            $0.code == .conflictingPrimaryProviderIdentity && $0.severity == .requiresReview
        })
    }

    @Test("Provider identity collision across restaurants is never silently merged")
    func providerIdentityCollisionAcrossRestaurants() throws {
        var first = LegacyFixture.restaurant(id: "r1", amapPoiID: "")
        first["placeIdentities"] = [LegacyFixture.identity(provider: "apple_maps", externalID: "same", primary: true)]
        var second = LegacyFixture.restaurant(id: "r2", amapPoiID: "")
        second["placeIdentities"] = [LegacyFixture.identity(provider: "apple_maps", externalID: "same", primary: true)]
        var envelope = LegacyFixture.envelope()
        envelope["restaurants"] = [first, second]
        let graph = try decoder.decode(LegacyFixture.data(envelope))
        #expect(graph.restaurants.count == 2)
        #expect(graph.conversionReport.issues.contains { $0.code == .providerIdentityCollisionAcrossRestaurants })
    }

    @Test("Nil-heavy and rich Visit values preserve absence, null, zero, and text")
    func nullableAndRichVisitConversion() throws {
        var nilHeavy = LegacyFixture.visit(id: "v1", restaurantID: "r1")
        nilHeavy["rating"] = NSNull()
        nilHeavy["myActualSpend"] = NSNull()
        nilHeavy["queueDuration"] = NSNull()
        nilHeavy["diningOccasions"] = []
        nilHeavy["note"] = ""

        var rich = LegacyFixture.visit(id: "v2", restaurantID: "r1")
        rich["rating"] = 4.5
        rich["totalPrice"] = 328.5
        rich["myActualSpend"] = 160
        rich["paymentMode"] = "aa"
        rich["partySize"] = 2
        rich["queueDuration"] = "under30"
        rich["diningOccasions"] = ["friends"]
        rich["diningOccasion"] = "celebration"
        rich["specialNotes"] = "靠窗"
        rich["noiseLevel"] = "normal"
        rich["diningDuration"] = "under90"
        rich["portionLevel"] = "generous"
        rich["transportConvenience"] = "convenient"

        var envelope = LegacyFixture.envelope()
        envelope["restaurants"] = [LegacyFixture.restaurant(id: "r1")]
        envelope["visits"] = [nilHeavy, rich]
        let graph = try decoder.decode(LegacyFixture.data(envelope))

        let first = try #require(graph.visits.first(where: { $0.sourceID == "v1" }))
        #expect(first.rating == nil)
        #expect(first.myActualSpend == nil)
        #expect(first.diningOccasions == [])
        #expect(first.note == "")
        let second = try #require(graph.visits.first(where: { $0.sourceID == "v2" }))
        #expect(second.rating?.rawValue == 4.5)
        #expect(second.totalPrice?.rawValue == "328.50")
        #expect(second.diningOccasions?.map(\.rawValue) == ["friends", "celebration"])
        #expect(second.specialNotes == "靠窗")
    }

    @Test("Embedded dishes split by visit and are never merged by name")
    func embeddedDishAndVisitDishConversion() throws {
        var firstVisit = LegacyFixture.visit(id: "v1", restaurantID: "r1")
        firstVisit["dishes"] = [
            LegacyFixture.dish(id: "legacy-d1", name: "招牌饭", photoID: "p-dish"),
            LegacyFixture.dish(id: "legacy-d2", name: "招牌饭"),
        ]
        var secondVisit = LegacyFixture.visit(id: "v2", restaurantID: "r1")
        secondVisit["dishes"] = [LegacyFixture.dish(id: "legacy-d1", name: "招牌饭")]
        var envelope = LegacyFixture.envelope()
        envelope["restaurants"] = [LegacyFixture.restaurant(id: "r1")]
        envelope["visits"] = [firstVisit, secondVisit]
        envelope["photos"] = [LegacyFixture.photo(id: "p-dish", kind: "dish")]
        let graph = try decoder.decode(LegacyFixture.data(envelope))

        #expect(graph.dishes.count == 3)
        #expect(graph.visitDishes.count == 3)
        #expect(Set(graph.dishes.map(\.sourceID)).count == 3)
        #expect(graph.dishes.allSatisfy { $0.name == "招牌饭" })
        #expect(graph.visitDishes.allSatisfy { association in
            graph.dishes.contains { $0.sourceID == association.sourceDishID }
        })
    }

    @Test("Companion names normalize only inside one file and preserve the first display spelling")
    func companionNormalization() throws {
        var visit = LegacyFixture.visit(id: "v1", restaurantID: "r1")
        visit["companions"] = ["  小王  ", "小王", "ＡＢＣ", "ABC"]
        visit["companionIds"] = ["tm_other"]
        var envelope = LegacyFixture.envelope()
        envelope["restaurants"] = [LegacyFixture.restaurant(id: "r1")]
        envelope["visits"] = [visit]
        let graph = try decoder.decode(LegacyFixture.data(envelope))

        #expect(graph.companions.map(\.displayName).contains("小王"))
        #expect(graph.companions.filter { $0.displayName == "小王" }.count == 1)
        #expect(graph.companions.allSatisfy { $0.sourceID.hasPrefix("legacy-companion-") })
        #expect(graph.visits.first?.companionSourceIDs.count == graph.companions.count)
        #expect(graph.conversionReport.issues.contains { $0.code == .linkedSocialIdentityRemoved })
    }

    @Test("Derived private-directory IDs are stable within one file but isolated across files")
    func privateDirectoryFileIsolation() throws {
        var visit = LegacyFixture.visit(id: "v1", restaurantID: "r1")
        visit["companions"] = ["小王"]
        visit["recommendationSourceType"] = "friend"
        visit["recommendationSourceText"] = "老同学"
        var firstEnvelope = LegacyFixture.envelope()
        firstEnvelope["restaurants"] = [LegacyFixture.restaurant(id: "r1")]
        firstEnvelope["visits"] = [visit]
        var secondEnvelope = firstEnvelope
        secondEnvelope["exportedAt"] = "2026-08-30T12:00:00.000Z"

        let first = try decoder.decode(LegacyFixture.data(firstEnvelope))
        let repeated = try decoder.decode(LegacyFixture.data(firstEnvelope))
        let second = try decoder.decode(LegacyFixture.data(secondEnvelope))

        #expect(first.companions.first?.sourceID == repeated.companions.first?.sourceID)
        #expect(first.recommendationSources.first?.sourceID == repeated.recommendationSources.first?.sourceID)
        #expect(first.companions.first?.sourceID != second.companions.first?.sourceID)
        #expect(first.recommendationSources.first?.sourceID != second.recommendationSources.first?.sourceID)
    }

    @Test("Recommendation source preserves authored text and strips linked-user authority")
    func recommendationSourceNormalization() throws {
        var visit = LegacyFixture.visit(id: "v1", restaurantID: "r1")
        visit["recommendationSourceType"] = "xiaohongshu"
        visit["recommendationSourceText"] = "  一位美食博主  "
        visit["recommendationSourceUserId"] = "tm_other"
        var envelope = LegacyFixture.envelope()
        envelope["restaurants"] = [LegacyFixture.restaurant(id: "r1")]
        envelope["visits"] = [visit]
        let graph = try decoder.decode(LegacyFixture.data(envelope))

        #expect(graph.recommendationSources.first?.displayName == "一位美食博主")
        #expect(graph.recommendationSources.first?.sourceType == .xiaohongshu)
        #expect(graph.visits.first?.recommendationSourceID == graph.recommendationSources.first?.sourceID)
        #expect(graph.conversionReport.securityAuthorityFieldsRemoved.contains {
            $0.field == "recommendationSourceUserId"
        })
    }

    @Test("Photo metadata survives but provider locators, transient state, and binary authority do not")
    func photoMetadataOnlyConversion() throws {
        var envelope = LegacyFixture.envelope()
        envelope["restaurants"] = [LegacyFixture.restaurant(id: "r1")]
        envelope["visits"] = [LegacyFixture.visit(id: "v1", restaurantID: "r1")]
        envelope["photos"] = [LegacyFixture.photo(id: "p1", kind: "visit", visitID: "v1")]
        let graph = try decoder.decode(LegacyFixture.data(envelope))

        let photo = try #require(graph.photos.first)
        #expect(photo.parent.entityType == .visit)
        #expect(photo.parent.sourceID == "v1")
        #expect(photo.fileName == "meal.jpg")
        #expect(photo.binaryAvailable == false)
        #expect(graph.conversionReport.issues.contains { $0.code == .photoProviderLocatorRemoved })
        #expect(graph.conversionReport.issues.contains { $0.code == .photoTransientStateRemoved })
        #expect(graph.conversionReport.issues.contains { $0.code == .photoBinaryUnavailable })
    }

    @Test("Inline marker, visit, dish, avatar, and list-cover binaries are measured then discarded")
    func inlineBinariesAreNotStaged() throws {
        var restaurant = LegacyFixture.restaurant(id: "r1")
        restaurant["markerImageData"] = "data:image/png;base64,QUJDRA=="
        var visit = LegacyFixture.visit(id: "v1", restaurantID: "r1")
        visit["photos"] = ["data:image/jpeg;base64,QUJDRA=="]
        var dish = LegacyFixture.dish(id: "d1", name: "菜")
        dish["imageData"] = "data:image/png;base64,QUJDRA=="
        visit["dishes"] = [dish]
        var profile = LegacyFixture.profile(id: "u1")
        profile["avatarImageData"] = "data:image/png;base64,QUJDRA=="
        var list = LegacyFixture.list(id: "l1")
        list["customCoverImageData"] = "data:image/png;base64,QUJDRA=="
        var envelope = LegacyFixture.envelope()
        envelope["restaurants"] = [restaurant]
        envelope["visits"] = [visit]
        envelope["users"] = [profile]
        envelope["restaurantLists"] = [list]
        let graph = try decoder.decode(LegacyFixture.data(envelope))

        let inline = graph.conversionReport.issues.filter { $0.code == .inlineBinaryDiscarded }
        #expect(Set(inline.compactMap(\.field)) == [
            "markerImageData", "photos", "imageData", "avatarImageData", "customCoverImageData",
        ])
        #expect(inline.allSatisfy { ($0.approximateByteCount ?? 0) > 0 })
    }

    @Test("Profile keeps presentation only; auth, email, membership, role, and token values disappear")
    func profileSecuritySanitization() throws {
        var profile = LegacyFixture.profile(id: "legacy-user")
        profile["email"] = "private@example.invalid"
        profile["authProvider"] = "apple"
        profile["authSubject"] = "apple-secret-subject"
        profile["membershipTier"] = "member"
        profile["role"] = "admin"
        profile["accessToken"] = "do-not-leak-token"
        var envelope = LegacyFixture.envelope()
        envelope["users"] = [profile]
        envelope["refreshToken"] = "root-token-must-not-leak"
        let graph = try decoder.decode(LegacyFixture.data(envelope))

        #expect(graph.profiles.first?.sourceID == "legacy-user")
        #expect(graph.profiles.first?.displayName == "示例用户")
        #expect(graph.conversionReport.securityAuthorityFieldsRemoved.count >= 6)
        let encoded = try JSONEncoder().encode(graph)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(!text.contains("private@example.invalid"))
        #expect(!text.contains("apple-secret-subject"))
        #expect(!text.contains("do-not-leak-token"))
        #expect(!text.contains("root-token-must-not-leak"))
        #expect(graph.conversionReport.securityAuthorityFieldsRemoved.contains {
            $0.entityType == .envelope && $0.field == "refreshToken"
        })
    }

    @Test("Friendships and shared meals are count-only; follows are explicitly absent")
    func socialAuthorityIsIgnored() throws {
        var visit = LegacyFixture.visit(id: "v1", restaurantID: "r1")
        visit["sharedMealId"] = "shared-1"
        var envelope = LegacyFixture.envelope()
        envelope["restaurants"] = [LegacyFixture.restaurant(id: "r1")]
        envelope["visits"] = [visit]
        envelope["friendships"] = [["requesterId": "secret-a", "addresseeId": "secret-b"]]
        envelope["sharedMeals"] = [["createdByUserId": "secret-a"]]
        envelope["sharedMealParticipants"] = [["userId": "secret-b"]]
        let graph = try decoder.decode(LegacyFixture.data(envelope))

        #expect(graph.conversionReport.sourceCounts.friendships == 1)
        #expect(graph.conversionReport.sourceCounts.sharedMeals == 1)
        #expect(graph.conversionReport.sourceCounts.sharedMealParticipants == 1)
        #expect(graph.conversionReport.issues.contains { $0.code == .legacyFormatDoesNotContainFollows })
        #expect(graph.conversionReport.issues.contains { $0.code == .sharedMealReferenceIsNonAuthoritative })
        let reportText = String(decoding: try JSONEncoder().encode(graph.conversionReport), as: UTF8.self)
        #expect(!reportText.contains("secret-a"))
        #expect(!reportText.contains("secret-b"))
    }

    @Test("Lists preserve order and references without trusting owner or inline cover data")
    func listConversion() throws {
        var list = LegacyFixture.list(id: "l1")
        list["userId"] = "forged-owner"
        var envelope = LegacyFixture.envelope()
        envelope["restaurants"] = [LegacyFixture.restaurant(id: "r1")]
        envelope["restaurantLists"] = [list]
        envelope["restaurantListItems"] = [
            LegacyFixture.listItem(id: "i2", listID: "l1", restaurantID: "r1", position: 2),
            LegacyFixture.listItem(id: "i1", listID: "l1", restaurantID: "r1", position: 1),
        ]
        let graph = try decoder.decode(LegacyFixture.data(envelope))
        #expect(graph.restaurantLists.first?.title == "周末食单")
        #expect(graph.restaurantListItems.map(\.position) == [1, 2])
        #expect(graph.conversionReport.securityAuthorityFieldsRemoved.contains { $0.field == "userId" })
    }

    @Test("Deleted records become minimal tombstones and do not retain business payload")
    func tombstoneConversion() throws {
        let deletedRestaurant: [String: Any] = [
            "id": "r-deleted",
            "name": "不应保留",
            "longTermNote": "敏感旧备注",
            "deletedAt": "2026-08-20T00:00:00.000Z",
        ]
        var deletedVisit = LegacyFixture.visit(id: "v-deleted", restaurantID: "r-deleted")
        deletedVisit["deletedAt"] = "2026-08-21T00:00:00.000Z"
        deletedVisit["dishes"] = [LegacyFixture.dish(id: "d1", name: "不应保留")]
        var envelope = LegacyFixture.envelope()
        envelope["restaurants"] = [deletedRestaurant]
        envelope["visits"] = [deletedVisit]
        let graph = try decoder.decode(LegacyFixture.data(envelope))

        #expect(graph.restaurants.isEmpty)
        #expect(graph.visits.isEmpty)
        #expect(graph.dishes.isEmpty)
        #expect(graph.tombstones.count == 2)
        let text = String(decoding: try JSONEncoder().encode(graph), as: UTF8.self)
        #expect(!text.contains("敏感旧备注"))
        #expect(!text.contains("不应保留"))
    }

    @Test("Broken Restaurant, Visit, Photo, List, and Dish references block future import")
    func referentialIntegrity() throws {
        var visit = LegacyFixture.visit(id: "v1", restaurantID: "missing-r")
        visit["photoIds"] = ["missing-photo"]
        visit["dishes"] = [LegacyFixture.dish(id: "d1", name: "菜", photoID: "missing-dish-photo")]
        var envelope = LegacyFixture.envelope()
        envelope["visits"] = [visit]
        envelope["restaurantLists"] = [LegacyFixture.list(id: "l1")]
        envelope["restaurantListItems"] = [
            LegacyFixture.listItem(id: "i1", listID: "missing-list", restaurantID: "missing-r", position: 0),
        ]
        let graph = try decoder.decode(LegacyFixture.data(envelope))

        #expect(graph.conversionReport.blockingIssues.count >= 5)
        #expect(graph.conversionReport.brokenReferences.contains { $0.entityType == .visit && $0.field == "restaurantId" })
        #expect(graph.conversionReport.brokenReferences.contains { $0.entityType == .restaurantListItem && $0.field == "listId" })
        #expect(graph.conversionReport.requiresReview)
    }

    @Test("Unknown fields and top-level collections are reported, never passed through")
    func unknownFields() throws {
        var restaurant = LegacyFixture.restaurant(id: "r1")
        restaurant["futureRestaurantFlavor"] = "raw-value-must-not-pass"
        var envelope = LegacyFixture.envelope()
        envelope["restaurants"] = [restaurant]
        envelope["futureEntities"] = [["raw": "unknown-payload"]]
        envelope["futureScalar"] = "unknown-scalar"
        let graph = try decoder.decode(LegacyFixture.data(envelope))

        #expect(graph.conversionReport.issues.contains {
            $0.code == .unknownFieldDiscarded && $0.field == "futureRestaurantFlavor"
        })
        #expect(graph.conversionReport.issues.contains {
            $0.code == .unknownTopLevelCollectionDiscarded && $0.field == "futureEntities"
        })
        let text = String(decoding: try JSONEncoder().encode(graph), as: UTF8.self)
        #expect(!text.contains("raw-value-must-not-pass"))
        #expect(!text.contains("unknown-payload"))
    }

    @Test("Retired Visit ideas are detected by name and never staged")
    func deprecatedVisitFields() throws {
        var visit = LegacyFixture.visit(id: "v1", restaurantID: "r1")
        visit["willingToReturn"] = true
        visit["recommendedDishes"] = ["菜 A"]
        visit["avoidDishes"] = ["菜 B"]
        visit["seatSituation"] = "靠窗"
        visit["reservationDetails"] = "提前一天"
        visit["bestVisitTime"] = "周末"
        var envelope = LegacyFixture.envelope()
        envelope["restaurants"] = [LegacyFixture.restaurant(id: "r1")]
        envelope["visits"] = [visit]
        let graph = try decoder.decode(LegacyFixture.data(envelope))

        #expect(Set(graph.conversionReport.deprecatedFields.compactMap(\.field)) == [
            "willingToReturn", "recommendedDishes", "avoidDishes",
            "seatSituation", "reservationDetails", "bestVisitTime",
        ])
        let text = String(decoding: try JSONEncoder().encode(graph.visits), as: UTF8.self)
        #expect(!text.contains("willingToReturn"))
        #expect(!text.contains("recommendedDishes"))
    }

    @Test("Duplicate IDs and invalid records are blocking, deterministic diagnostics")
    func duplicateAndInvalidRecords() throws {
        var envelope = LegacyFixture.envelope()
        envelope["restaurants"] = [
            LegacyFixture.restaurant(id: "r1"),
            LegacyFixture.restaurant(id: "r1"),
            ["id": "", "name": "bad", "latitude": 999, "longitude": 0],
            "primitive",
        ]
        let graph = try decoder.decode(LegacyFixture.data(envelope))
        #expect(graph.restaurants.count == 1)
        #expect(graph.conversionReport.blockingIssues.contains { $0.code == .duplicateSourceID })
        #expect(graph.conversionReport.invalidRecords.count >= 2)
    }

    @Test("The same bytes decode to byte-identical staging output 100 times")
    func determinism() throws {
        let source = LegacyFixture.data(LegacyFixture.fullEnvelope())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let baseline = try encoder.encode(decoder.decode(source))
        for _ in 0 ..< 100 {
            let result = try encoder.encode(decoder.decode(source))
            #expect(result == baseline)
        }
    }

    @Test("Synthetic 1k/10k/5k graph decodes within a bounded simulator budget")
    func largeFixturePerformance() throws {
        let source = LegacyFixture.largeFixture(
            restaurantCount: 1_000,
            visitCount: 10_000,
            embeddedDishCount: 5_000,
            photoCount: 200,
            listCount: 50
        )
        let clock = ContinuousClock()
        let started = clock.now
        let graph = try decoder.decode(source)
        let elapsed = started.duration(to: clock.now)
        let components = elapsed.components
        let seconds = Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000

        print(String(format: "LEGACY_V4_PERF_SECONDS=%.3f BYTES=%d", seconds, source.count))
        #expect(graph.restaurants.count == 1_000)
        #expect(graph.visits.count == 10_000)
        #expect(graph.dishes.count == 5_000)
        #expect(seconds < 30)
    }

    private func fixtureData(named name: String) throws -> Data {
        let bundle = Bundle(for: LegacyBackupContractBundleMarker.self)
        let candidates = [
            bundle.url(forResource: name, withExtension: "json"),
            bundle.url(forResource: name, withExtension: "json", subdirectory: "backup/fixtures"),
            bundle.url(forResource: name, withExtension: "json", subdirectory: "contracts/backup/fixtures"),
        ]
        return try Data(contentsOf: try #require(candidates.compactMap { $0 }.first))
    }
}

private enum LegacyFixture {
    static let timestamp = "2026-08-29T12:00:00.000Z"

    static func envelope() -> [String: Any] {
        [
            "app": "Taste Map",
            "version": 4,
            "environment": "development",
            "databaseName": "FoodMapDB",
            "exportedAt": timestamp,
            "restaurants": [],
            "visits": [],
            "photos": [],
            "users": [],
            "friendships": [],
            "sharedMeals": [],
            "sharedMealParticipants": [],
            "restaurantLists": [],
            "restaurantListItems": [],
        ]
    }

    static func restaurant(
        id: String,
        status: String = "visited",
        amapPoiID: String = "amap-default"
    ) -> [String: Any] {
        [
            "id": id,
            "userId": "legacy-owner",
            "amapPoiId": amapPoiID,
            "name": "真实测试餐厅 \(id)",
            "address": "测试路 1 号",
            "city": "上海",
            "latitude": 31.2304,
            "longitude": 121.4737,
            "status": status,
            "preferenceLevel": "like",
            "overallRating": NSNull(),
            "foodRating": NSNull(),
            "environmentRating": NSNull(),
            "serviceRating": NSNull(),
            "valueRating": NSNull(),
            "tags": ["本帮菜"],
            "longTermNote": "",
            "pricePerPerson": NSNull(),
            "phone": NSNull(),
            "openingHours": NSNull(),
            "markerType": "emoji",
            "markerImageData": NSNull(),
            "markerPhotoId": NSNull(),
            "merchantImageUrl": NSNull(),
            "markerEmoji": "🍜",
            "createdAt": timestamp,
            "updatedAt": timestamp,
            "deletedAt": NSNull(),
        ]
    }

    static func identity(provider: String, externalID: String, primary: Bool) -> [String: Any] {
        [
            "provider": provider,
            "externalId": externalID,
            "isPrimary": primary,
            "createdAt": timestamp,
            "updatedAt": timestamp,
        ]
    }

    static func visit(id: String, restaurantID: String) -> [String: Any] {
        [
            "id": id,
            "userId": "legacy-owner",
            "restaurantId": restaurantID,
            "visitedAt": timestamp,
            "rating": NSNull(),
            "visibility": "private",
            "diningMode": "dine_in",
            "totalPrice": NSNull(),
            "myActualSpend": NSNull(),
            "paymentMode": NSNull(),
            "pricePerPerson": NSNull(),
            "partySize": NSNull(),
            "queueDuration": NSNull(),
            "diningOccasions": [],
            "diningOccasion": NSNull(),
            "diningOccasionText": "",
            "valueRating": NSNull(),
            "environmentRating": NSNull(),
            "serviceRating": NSNull(),
            "valueTags": [],
            "environmentTags": [],
            "serviceTags": [],
            "noiseLevel": NSNull(),
            "diningDuration": NSNull(),
            "portionLevel": NSNull(),
            "transportConvenience": NSNull(),
            "specialNotes": "",
            "recommendationSourceType": NSNull(),
            "recommendationSourceUserId": NSNull(),
            "recommendationSourceText": "",
            "sharedMealId": NSNull(),
            "companions": [],
            "companionIds": [],
            "dishes": [],
            "note": "",
            "photos": [],
            "photoIds": [],
            "createdAt": timestamp,
            "updatedAt": timestamp,
            "deletedAt": NSNull(),
        ]
    }

    static func dish(id: String, name: String, photoID: String? = nil) -> [String: Any] {
        [
            "id": id,
            "name": name,
            "taste": "好吃",
            "rating": 4.5,
            "price": 38,
            "imageData": NSNull(),
            "photoId": photoID ?? NSNull(),
        ]
    }

    static func photo(
        id: String,
        kind: String,
        restaurantID: String? = nil,
        visitID: String? = nil
    ) -> [String: Any] {
        [
            "id": id,
            "userId": "legacy-owner",
            "restaurantId": restaurantID ?? NSNull(),
            "visitId": visitID ?? NSNull(),
            "kind": kind,
            "storageProvider": "r2",
            "storageKey": "private/storage/key",
            "thumbnailStorageKey": "private/thumb/key",
            "thumbnailFileSize": 1200,
            "driveAccountId": "drive-account",
            "driveFileId": "drive-file",
            "fileName": "meal.jpg",
            "mimeType": "image/jpeg",
            "fileSize": 12_345,
            "width": 1200,
            "height": 800,
            "visibility": "private",
            "syncStatus": "synced",
            "createdAt": timestamp,
            "updatedAt": timestamp,
            "deletedAt": NSNull(),
            "localState": "synced",
            "lastError": NSNull(),
        ]
    }

    static func profile(id: String) -> [String: Any] {
        [
            "id": id,
            "nickname": "示例用户",
            "bio": "记录真实味道",
            "city": "上海",
            "avatarImageData": NSNull(),
            "avatarPhotoId": NSNull(),
            "avatarPresetId": "polar-bear",
            "mapVisibility": "private",
            "createdAt": timestamp,
            "updatedAt": timestamp,
            "deletedAt": NSNull(),
        ]
    }

    static func list(id: String) -> [String: Any] {
        [
            "id": id,
            "title": "周末食单",
            "description": "想再去的地方",
            "visibility": "private",
            "isRanked": true,
            "coverMode": "automatic",
            "customCoverImageData": NSNull(),
            "customCoverPhotoId": NSNull(),
            "createdAt": timestamp,
            "updatedAt": timestamp,
            "deletedAt": NSNull(),
        ]
    }

    static func listItem(
        id: String,
        listID: String,
        restaurantID: String,
        position: Int
    ) -> [String: Any] {
        [
            "id": id,
            "listId": listID,
            "restaurantId": restaurantID,
            "position": position,
            "note": "",
            "createdAt": timestamp,
            "updatedAt": timestamp,
            "deletedAt": NSNull(),
        ]
    }

    static func fullEnvelope() -> [String: Any] {
        var restaurant = restaurant(id: "r1", amapPoiID: "")
        restaurant["placeIdentities"] = [
            identity(provider: "apple_maps", externalID: "apple-r1", primary: true),
        ]
        restaurant["markerPhotoId"] = "p-marker"
        var visit = visit(id: "v1", restaurantID: "r1")
        visit["companions"] = ["小王"]
        visit["recommendationSourceType"] = "xiaohongshu"
        visit["recommendationSourceText"] = "本地博主"
        visit["dishes"] = [dish(id: "d1", name: "招牌菜", photoID: "p-dish")]
        visit["photoIds"] = ["p-visit"]
        var profile = profile(id: "legacy-user")
        profile["avatarPhotoId"] = "p-avatar"
        var envelope = envelope()
        envelope["restaurants"] = [restaurant]
        envelope["visits"] = [visit]
        envelope["photos"] = [
            photo(id: "p-marker", kind: "restaurant-marker", restaurantID: "r1"),
            photo(id: "p-visit", kind: "visit", visitID: "v1"),
            photo(id: "p-dish", kind: "dish"),
            photo(id: "p-avatar", kind: "avatar"),
        ]
        envelope["users"] = [profile]
        envelope["friendships"] = [["id": "friend-1"]]
        envelope["sharedMeals"] = [["id": "meal-1"]]
        envelope["sharedMealParticipants"] = [["id": "participant-1"]]
        envelope["restaurantLists"] = [list(id: "l1")]
        envelope["restaurantListItems"] = [
            listItem(id: "i1", listID: "l1", restaurantID: "r1", position: 0),
        ]
        return envelope
    }

    static func largeFixture(
        restaurantCount: Int,
        visitCount: Int,
        embeddedDishCount: Int,
        photoCount: Int,
        listCount: Int
    ) -> Data {
        var envelope = envelope()
        envelope["restaurants"] = (0 ..< restaurantCount).map { index in
            restaurant(id: "r-\(index)", amapPoiID: "amap-\(index)")
        }
        envelope["visits"] = (0 ..< visitCount).map { index in
            var value = visit(id: "v-\(index)", restaurantID: "r-\(index % restaurantCount)")
            if index < embeddedDishCount {
                value["dishes"] = [dish(id: "d-\(index)", name: "菜 \(index)")]
            }
            return value
        }
        envelope["photos"] = (0 ..< photoCount).map { index in
            photo(id: "p-\(index)", kind: "visit", visitID: "v-\(index)")
        }
        envelope["restaurantLists"] = (0 ..< listCount).map { list(id: "l-\($0)") }
        envelope["restaurantListItems"] = (0 ..< listCount).map {
            listItem(id: "li-\($0)", listID: "l-\($0)", restaurantID: "r-\($0)", position: 0)
        }
        return data(envelope)
    }

    static func data(_ object: Any) -> Data {
        // Fixtures are synthetic dictionaries composed only of JSON primitives.
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

private final class LegacyBackupContractBundleMarker {}
