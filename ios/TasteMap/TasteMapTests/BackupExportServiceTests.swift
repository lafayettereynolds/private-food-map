import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("Backup v1 export engine")
@MainActor
struct BackupExportServiceTests {
    private let userA = "tm_backup_user_a"
    private let userB = "tm_backup_user_b"
    private let exportedAt = Date(timeIntervalSince1970: 1_788_000_000)
    private let exportID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

    @Test("Empty account exports a valid offline envelope")
    func emptyAccount() throws {
        let harness = try makeHarness()
        let envelope = try harness.service.makeEnvelope(
            input: emptyInput,
            currentUserID: userA,
            exportedAt: exportedAt,
            exportID: exportID
        )

        #expect(envelope.scope.includesPhotoBinaries == false)
        #expect(envelope.metadata.entityCounts == zeroCounts)
        #expect(envelope.metadata.tombstoneCount == 0)
        #expect(try harness.service.verifyIntegrity(envelope))
        let roundTrip = try JSONDecoder().decode(
            BackupEnvelopeV1.self,
            from: harness.service.encodeAndVerify(envelope)
        )
        #expect(roundTrip == envelope)
    }

    @Test("Rich export maps all ten entities, nullable values, providers, lists, and tombstones")
    func richAccount() throws {
        let harness = try makeHarness()
        let input = try richInput(userID: userA)
        let envelope = try harness.service.makeEnvelope(
            input: input,
            currentUserID: userA,
            exportedAt: exportedAt,
            exportID: exportID
        )
        let entities = envelope.entities

        #expect(entities.restaurants.count == 3)
        #expect(entities.restaurants.flatMap(\.placeIdentities).map(\.provider).contains(.appleMaps))
        #expect(entities.restaurants.flatMap(\.placeIdentities).map(\.provider).contains(.amap))
        #expect(entities.restaurants.flatMap(\.placeIdentities).map(\.provider).contains(.manual))
        #expect(entities.visits.count == 2)
        #expect(entities.visits.first(where: { $0.id == "visit-nil" })?.rating == nil)
        #expect(entities.visits.first(where: { $0.id == "visit-nil" })?.myActualSpend == nil)
        #expect(entities.visits.first(where: { $0.id == "visit-nil" })?.partySize == nil)
        #expect(entities.visits.first(where: { $0.id == "visit-rich" })?.myActualSpend?.rawValue == "128.50")
        #expect(entities.dishes.count == 1)
        #expect(entities.visitDishes.count == 1)
        #expect(entities.photos.count == 1)
        #expect(entities.companions.count == 1)
        #expect(entities.recommendationSources.count == 1)
        #expect(entities.profiles.count == 1)
        #expect(entities.restaurantLists.count == 1)
        #expect(entities.restaurantListItems.map(\.position) == [0, 1])
        #expect(entities.restaurantListItems.map(\.id) == ["list-item-z", "list-item-a"])
        #expect(envelope.tombstones.count == 1)
        #expect(envelope.tombstones.first?.entityType == .companion)
        #expect(envelope.metadata.entityCounts == counts(for: entities))
        #expect(envelope.metadata.tombstoneCount == envelope.tombstones.count)
    }

    @Test("Actual JSON uses explicit null, exact UTC milliseconds, exact decimal, and a valid digest")
    func scalarAndIntegrityOutput() throws {
        let harness = try makeHarness()
        let envelope = try harness.service.makeEnvelope(
            input: try richInput(userID: userA),
            currentUserID: userA,
            exportedAt: exportedAt,
            exportID: exportID
        )
        let data = try harness.service.encodeAndVerify(envelope)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entities = try #require(object["entities"] as? [String: Any])
        let visits = try #require(entities["visits"] as? [[String: Any]])
        let nilVisit = try #require(visits.first { $0["id"] as? String == "visit-nil" })
        let richVisit = try #require(visits.first { $0["id"] as? String == "visit-rich" })

        #expect(nilVisit["rating"] is NSNull)
        #expect(nilVisit["myActualSpend"] is NSNull)
        #expect(nilVisit["partySize"] is NSNull)
        #expect(richVisit["myActualSpend"] as? String == "128.50")
        #expect((richVisit["visitedAt"] as? String)?.hasSuffix(".000Z") == true)
        #expect(try harness.service.verifyIntegrity(envelope))
        #expect(envelope.integrity.digest.count == 64)
    }

    @Test("Explicit allowlist excludes paths, provider locators, linked identities, owner, auth, sync, and entitlement authority")
    func securityDenylist() throws {
        let harness = try makeHarness()
        let envelope = try harness.service.makeEnvelope(
            input: try richInput(userID: userA),
            currentUserID: userA,
            exportedAt: exportedAt,
            exportID: exportID
        )
        let data = try harness.service.encodeAndVerify(envelope)
        let json = try #require(String(data: data, encoding: .utf8))
        let object = try JSONSerialization.jsonObject(with: data)
        let keys = collectKeys(object)

        for forbidden in [
            "userId", "ownerUserId", "accessToken", "refreshToken", "appleSub", "authSubject",
            "membership", "premium", "admin", "role", "StoreKit", "serverVersion", "syncMutation",
            "syncStatus", "retryCount", "localPath", "localFileRelativePath", "storageKey",
            "providerAccountId", "remoteRecordData",
        ] {
            #expect(!keys.contains(forbidden), "Forbidden key: \(forbidden)")
        }
        #expect(!json.contains("r2/private/storage-key"))
        #expect(!json.contains("Photos/private/original.heic"))
        #expect(!json.contains("tm_linked_private_identity"))
        #expect(!json.contains(userA))
    }

    @Test("User A and User B exports contain only their owned graph after account switching")
    func currentUserIsolationAndSwitching() throws {
        let harness = try makeHarness()
        let input = try twoUserInput()

        let exportA = try harness.service.makeEnvelope(
            input: input, currentUserID: userA, exportedAt: exportedAt, exportID: exportID
        )
        let exportB = try harness.service.makeEnvelope(
            input: input,
            currentUserID: userB,
            exportedAt: exportedAt,
            exportID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        )
        let jsonA = try #require(String(data: harness.service.encodeAndVerify(exportA), encoding: .utf8))
        let jsonB = try #require(String(data: harness.service.encodeAndVerify(exportB), encoding: .utf8))

        #expect(exportA.entities.restaurants.map(\.id) == ["restaurant-a"])
        #expect(exportA.entities.visits.map(\.id) == ["visit-a"])
        #expect(exportA.entities.companions.map(\.id) == ["companion-a"])
        #expect(!jsonA.contains("B_PRIVATE_NAME"))
        #expect(!jsonA.contains("B_PRIVATE_NOTE"))

        #expect(exportB.entities.restaurants.map(\.id) == ["restaurant-b"])
        #expect(exportB.entities.visits.map(\.id) == ["visit-b"])
        #expect(exportB.entities.companions.map(\.id) == ["companion-b"])
        #expect(!jsonB.contains("A_PRIVATE_NAME"))
        #expect(!jsonB.contains("A_PRIVATE_NOTE"))
    }

    @Test("Ambiguous device-local ownership fails closed instead of leaking across users")
    func ambiguousLocalOwnerFailsClosed() throws {
        let local = Restaurant(
            name: "AMBIGUOUS_PRIVATE_RESTAURANT",
            address: "private",
            latitude: 30,
            longitude: 120,
            remoteID: "ambiguous-local"
        )
        let input = BackupExportInput(
            restaurants: [local], visits: [], dishes: [], visitDishes: [], photos: [], companions: [],
            recommendationSources: [],
            profiles: [UserProfile(tasteMapUserID: userA), UserProfile(tasteMapUserID: userB)],
            restaurantLists: [], restaurantListItems: []
        )
        let harness = try makeHarness()
        #expect(throws: BackupExportError.self) {
            try harness.service.makeEnvelope(
                input: input, currentUserID: userB, exportedAt: exportedAt, exportID: exportID
            )
        }
    }

    @Test("Orphan Visit, Dish, VisitDish, Photo, avatar, and List relationships block export")
    func referentialIntegrityBlocksOrphans() throws {
        let orphan = Visit(
            restaurantId: UUID(), note: "orphan", remoteID: "orphan-visit"
        )
        let input = BackupExportInput(
            restaurants: [], visits: [orphan], dishes: [], visitDishes: [], photos: [], companions: [],
            recommendationSources: [], profiles: [], restaurantLists: [], restaurantListItems: []
        )
        let harness = try makeHarness()
        do {
            _ = try harness.service.makeEnvelope(
                input: input, currentUserID: userA, exportedAt: exportedAt, exportID: exportID
            )
            Issue.record("Expected structured orphan validation error")
        } catch let BackupExportError.validation(error) {
            #expect(error.issues.contains { $0.code == .orphanedReference && $0.entityType == .visit })
        }
    }

    @Test("Entity and set ordering is deterministic while list business order is preserved")
    func deterministicOrdering() throws {
        let harness = try makeHarness()
        let input = try richInput(userID: userA)
        let reversed = BackupExportInput(
            restaurants: Array(input.restaurants.reversed()),
            visits: Array(input.visits.reversed()),
            dishes: Array(input.dishes.reversed()),
            visitDishes: Array(input.visitDishes.reversed()),
            photos: Array(input.photos.reversed()),
            companions: Array(input.companions.reversed()),
            recommendationSources: Array(input.recommendationSources.reversed()),
            profiles: Array(input.profiles.reversed()),
            restaurantLists: Array(input.restaurantLists.reversed()),
            restaurantListItems: Array(input.restaurantListItems.reversed())
        )
        let first = try harness.service.makeEnvelope(
            input: input, currentUserID: userA, exportedAt: exportedAt, exportID: exportID
        )
        let second = try harness.service.makeEnvelope(
            input: reversed, currentUserID: userA, exportedAt: exportedAt, exportID: exportID
        )

        #expect(first == second)
        #expect(first.integrity.digest == second.integrity.digest)
        #expect(first.entities.restaurants.map(\.id) == first.entities.restaurants.map(\.id).sorted())
        #expect(first.entities.restaurantListItems.map(\.position) == [0, 1])
    }

    @Test("Export is read-only, offline, and creates no SyncMutation or timestamp changes")
    func noSyncSideEffects() throws {
        let harness = try makeHarness()
        let input = try richInput(userID: userA)
        for model in input.restaurants { harness.context.insert(model) }
        for model in input.visits { harness.context.insert(model) }
        for model in input.dishes { harness.context.insert(model) }
        for model in input.visitDishes { harness.context.insert(model) }
        for model in input.photos { harness.context.insert(model) }
        for model in input.companions { harness.context.insert(model) }
        for model in input.recommendationSources { harness.context.insert(model) }
        for model in input.profiles { harness.context.insert(model) }
        for model in input.restaurantLists { harness.context.insert(model) }
        for model in input.restaurantListItems { harness.context.insert(model) }
        try harness.context.save()

        let beforeDates = Dictionary(uniqueKeysWithValues: input.visits.map { ($0.id, $0.updatedAt) })
        let beforeMutations = try harness.context.fetchCount(FetchDescriptor<SyncMutation>())
        let artifact = try harness.service.export(currentUserID: userA)
        let afterMutations = try harness.context.fetchCount(FetchDescriptor<SyncMutation>())

        #expect(beforeMutations == afterMutations)
        #expect(input.visits.allSatisfy { beforeDates[$0.id] == $0.updatedAt })
        #expect(FileManager.default.fileExists(atPath: artifact.fileURL.path))
        #expect(artifact.fileURL.lastPathComponent == "TasteMap-Backup-2026-08-29.json")
        try harness.service.removeTemporaryExport(artifact)
        #expect(!FileManager.default.fileExists(atPath: artifact.fileURL.path))
    }

    @Test("Protected temp files clean up after completion, cancel, failure, age, and count without touching unrelated files")
    func protectedTemporaryFilesAndCleanup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupExportTests-\(UUID().uuidString)", isDirectory: true)
        let store = BackupExportTemporaryFileStore(
            rootDirectoryURL: root,
            maximumAge: 60,
            maximumExportCount: 1
        )
        let firstID = UUID()
        let first = try store.write(Data("{}".utf8), exportedAt: exportedAt, exportID: firstID)
        #expect(first.lastPathComponent == "TasteMap-Backup-2026-08-29.json")
        #expect(FileManager.default.fileExists(atPath: first.path))
        let protection = try FileManager.default.attributesOfItem(atPath: first.path)[.protectionKey]
#if targetEnvironment(simulator)
        // CoreSimulator accepts file-protection attributes but may not expose
        // them through stat(2); a physical device must report `.complete`.
        #expect(protection == nil || protection as? FileProtectionType == .complete)
#else
        #expect(protection as? FileProtectionType == .complete)
#endif

        let unrelated = root.appendingPathComponent("unrelated.txt")
        try Data("keep".utf8).write(to: unrelated)
        try FileManager.default.setAttributes(
            [.modificationDate: exportedAt.addingTimeInterval(-120)],
            ofItemAtPath: first.deletingLastPathComponent().path
        )
        try store.cleanup(now: exportedAt)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))

        let second = try store.write(Data("{}".utf8), exportedAt: exportedAt, exportID: UUID())
        try store.removeArtifact(at: second) // share completed / cancelled / failed use the same cleanup path
        try store.removeArtifact(at: second) // idempotent completion race
        #expect(!FileManager.default.fileExists(atPath: second.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        try? FileManager.default.removeItem(at: root)
    }

    @Test("Unsafe Photo path-like file names fail instead of exporting raw storage metadata")
    func unsafePhotoMappingFails() throws {
        var input = try richInput(userID: userA)
        let original = try #require(input.photos.first)
        let unsafe = PhotoAsset(
            id: original.id,
            restaurantId: original.restaurantId,
            visitId: original.visitId,
            dishId: original.dishId,
            kind: original.kind,
            fileName: "../../private/photo.jpg",
            mimeType: original.mimeType,
            byteSize: original.byteSize,
            remoteID: original.remoteID
        )
        input = BackupExportInput(
            restaurants: input.restaurants, visits: input.visits, dishes: input.dishes,
            visitDishes: input.visitDishes, photos: [unsafe], companions: input.companions,
            recommendationSources: input.recommendationSources, profiles: input.profiles,
            restaurantLists: input.restaurantLists, restaurantListItems: input.restaurantListItems
        )
        let harness = try makeHarness()
        #expect(throws: BackupExportError.self) {
            try harness.service.makeEnvelope(
                input: input, currentUserID: userA, exportedAt: exportedAt, exportID: exportID
            )
        }
    }

    @Test("Large local graph exports deterministically with correct counts in a bounded time")
    func largeDatasetPerformance() throws {
        let restaurantCount = 1_000
        let visitCount = 10_000
        let dishCount = 5_000
        let restaurants = (0 ..< restaurantCount).map { index in
            Restaurant(
                id: stableUUID(index + 1),
                ownerUserID: userA,
                name: "Restaurant \(index)",
                address: "Address \(index)",
                latitude: 30,
                longitude: 120,
                remoteID: "large-restaurant-\(String(format: "%04d", index))"
            )
        }
        let visits = (0 ..< visitCount).map { index in
            Visit(
                id: stableUUID(20_000 + index),
                ownerUserID: userA,
                restaurantId: restaurants[index % restaurantCount].id,
                visitedAt: exportedAt,
                remoteID: "large-visit-\(String(format: "%05d", index))"
            )
        }
        let dishes = (0 ..< dishCount).map { index in
            let visit = visits[index]
            return Dish(
                id: stableUUID(40_000 + index),
                ownerUserID: userA,
                restaurantId: visit.restaurantId,
                visitId: visit.id,
                name: "Dish \(index)",
                remoteID: "large-dish-\(String(format: "%05d", index))"
            )
        }
        let associations = dishes.enumerated().map { index, dish in
            VisitDish(
                id: stableUUID(60_000 + index),
                ownerUserID: userA,
                restaurantId: dish.restaurantId,
                visitId: dish.visitId,
                dishId: dish.id,
                remoteID: "large-visit-dish-\(String(format: "%05d", index))"
            )
        }
        let photos = dishes.prefix(1_000).enumerated().map { index, dish in
            PhotoAsset(
                id: stableUUID(80_000 + index),
                ownerUserID: userA,
                restaurantId: dish.restaurantId,
                visitId: dish.visitId,
                dishId: dish.id,
                kind: .dish,
                fileName: "photo-\(index).jpg",
                mimeType: "image/jpeg",
                byteSize: 1_024,
                remoteID: "large-photo-\(String(format: "%04d", index))"
            )
        }
        for (dish, photo) in zip(dishes, photos) { dish.photoRemoteID = photo.remoteID }
        let input = BackupExportInput(
            restaurants: restaurants, visits: visits, dishes: dishes, visitDishes: associations,
            photos: photos, companions: [], recommendationSources: [],
            profiles: [UserProfile(tasteMapUserID: userA)],
            restaurantLists: [], restaurantListItems: []
        )
        let harness = try makeHarness()
        let started = CFAbsoluteTimeGetCurrent()
        let envelope = try harness.service.makeEnvelope(
            input: input, currentUserID: userA, exportedAt: exportedAt, exportID: exportID
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - started

        #expect(envelope.metadata.entityCounts.restaurants == restaurantCount)
        #expect(envelope.metadata.entityCounts.visits == visitCount)
        #expect(envelope.metadata.entityCounts.dishes == dishCount)
        #expect(envelope.metadata.entityCounts.visitDishes == dishCount)
        #expect(envelope.metadata.entityCounts.photos == 1_000)
        #expect(elapsed < 30, "Large export took \(elapsed) seconds")
    }

    @Test("Generated iOS export fixture is available to the shared JSON Schema pipeline")
    func generatedSchemaFixture() throws {
        let path = ProcessInfo.processInfo.environment["TASTEMAP_BACKUP_FIXTURE_OUTPUT"]
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "/tmp/backup.v1.ios-export.generated.json"
        let harness = try makeHarness()
        let envelope = try harness.service.makeEnvelope(
            input: try richInput(userID: userA),
            currentUserID: userA,
            exportedAt: exportedAt,
            exportID: exportID
        )
        try harness.service.encodeAndVerify(envelope).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private var emptyInput: BackupExportInput {
        BackupExportInput(
            restaurants: [], visits: [], dishes: [], visitDishes: [], photos: [], companions: [],
            recommendationSources: [], profiles: [], restaurantLists: [], restaurantListItems: []
        )
    }

    private var zeroCounts: BackupEntityCountsV1 {
        BackupEntityCountsV1(
            restaurants: 0, visits: 0, dishes: 0, visitDishes: 0, photos: 0,
            companions: 0, recommendationSources: 0, profiles: 0,
            restaurantLists: 0, restaurantListItems: 0
        )
    }

    private func counts(for entities: BackupEntitiesV1) -> BackupEntityCountsV1 {
        BackupEntityCountsV1(
            restaurants: entities.restaurants.count,
            visits: entities.visits.count,
            dishes: entities.dishes.count,
            visitDishes: entities.visitDishes.count,
            photos: entities.photos.count,
            companions: entities.companions.count,
            recommendationSources: entities.recommendationSources.count,
            profiles: entities.profiles.count,
            restaurantLists: entities.restaurantLists.count,
            restaurantListItems: entities.restaurantListItems.count
        )
    }

    private func makeHarness() throws -> Harness {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupExportHarness-\(UUID().uuidString)", isDirectory: true)
        let files = BackupExportTemporaryFileStore(rootDirectoryURL: root)
        let service = try BackupExportService(
            context: container.mainContext,
            source: BackupExportSourceInfo(
                appVersion: "1.0", appBuild: "1", environment: .development
            ),
            temporaryFiles: files,
            now: { exportedAt },
            makeExportID: { exportID }
        )
        return Harness(container: container, context: container.mainContext, service: service)
    }

    private func richInput(userID: String) throws -> BackupExportInput {
        let apple = try ownedRestaurant(
            localID: stableUUID(1), remoteID: "restaurant-apple", owner: userID,
            name: "Apple Maps Sushi", provider: .appleMaps, externalID: "apple-map-item-1"
        )
        let amap = try ownedRestaurant(
            localID: stableUUID(2), remoteID: "restaurant-amap", owner: userID,
            name: "AMap Noodles", provider: .amap, externalID: "B0AMAP1"
        )
        let manual = Restaurant(
            id: stableUUID(3), ownerUserID: userID,
            name: "Manual Cafe", address: "Manual Address", latitude: 30.3,
            longitude: 120.3, remoteID: "restaurant-manual"
        )
        let companion = DiningCompanion(
            id: stableUUID(10), ownerUserId: userID, displayName: "小王",
            linkedTasteMapUserId: "tm_linked_private_identity", remoteID: "companion-1"
        )
        let deletedCompanion = DiningCompanion(
            id: stableUUID(11), ownerUserId: userID, displayName: "已删除私人饭搭子",
            remoteID: "companion-deleted", deletedAt: exportedAt
        )
        let source = RecommendationSource(
            id: stableUUID(12), ownerUserId: userID, displayName: "朋友推荐",
            sourceType: .friend, linkedTasteMapUserId: "tm_linked_private_identity",
            remoteID: "source-1"
        )
        let nilVisit = Visit(
            id: stableUUID(20), ownerUserID: userID,
            restaurantId: amap.id, visitedAt: exportedAt,
            rating: nil, note: nil, myActualSpend: nil, partySize: nil,
            remoteID: "visit-nil"
        )
        let richVisit = Visit(
            id: stableUUID(21), ownerUserID: userID,
            restaurantId: apple.id, visitedAt: exportedAt,
            rating: 4.5, valueRating: 4, environmentRating: 4.5, serviceRating: 5,
            note: "真实私人备注", myActualSpend: Decimal(string: "128.50"),
            totalPrice: Decimal(string: "257.00"), pricePerPerson: Decimal(string: "128.50"),
            diningMode: .dineIn, visibility: .private, paymentMode: .aa,
            queueDuration: .under30, diningOccasions: [.friends],
            diningOccasionText: nil, valueTags: ["划算", "划算"], environmentTags: ["舒适"],
            serviceTags: ["周到"], noiseLevel: .normal, diningDuration: .under90,
            portionLevel: .generous, transportConvenience: .convenient,
            specialNotes: "靠窗", companionIDs: ["companion-1"], companionNames: ["小王"],
            recommendationSourceID: "source-1", recommendationSourceType: .friend,
            recommendationSourceUserID: "tm_linked_private_identity",
            recommendationSourceText: "朋友推荐", sharedMealID: "meal-reference-hint",
            partySize: 2, remoteID: "visit-rich"
        )
        let dish = Dish(
            id: stableUUID(30), ownerUserID: userID,
            restaurantId: apple.id, visitId: richVisit.id,
            name: "金枪鱼寿司", taste: "鲜", rating: 5,
            price: Decimal(string: "68.00"), photoRemoteID: "photo-1",
            remoteID: "dish-1"
        )
        let visitDish = VisitDish(
            id: stableUUID(31), ownerUserID: userID,
            restaurantId: apple.id, visitId: richVisit.id,
            dishId: dish.id, remoteID: "visit-dish-1"
        )
        let photo = PhotoAsset(
            id: stableUUID(40), ownerUserID: userID,
            restaurantId: apple.id, visitId: richVisit.id, dishId: dish.id,
            kind: .dish, storageProvider: .r2,
            storageKey: "r2/private/storage-key", providerAccountId: "drive-account-private",
            thumbnailStorageKey: "r2/private/thumb", fileName: "sushi.heic",
            mimeType: "image/heic", byteSize: 2_048, width: 1_200, height: 900,
            visibility: .private, localFileRelativePath: "Photos/private/original.heic",
            displayFileRelativePath: "Photos/private/display.jpg",
            thumbnailFileRelativePath: "Photos/private/thumb.jpg",
            displayContentHash: String(repeating: "a", count: 64),
            cachedStorageKey: "cached/private/storage", uploadState: .failed,
            uploadRetryCount: 9, uploadLastError: "private upload failure",
            remoteID: "photo-1"
        )
        let profile = UserProfile(
            id: stableUUID(50), tasteMapUserID: userID, displayName: "Lafayette",
            bio: "认真吃饭", city: "杭州", avatarPreset: .otter,
            visibility: .friends
        )
        let list = RestaurantList(
            id: stableUUID(60), remoteID: "list-1", ownerUserID: userID,
            title: "我的榜单", listDescription: "真实餐厅排序", visibility: .private,
            isRanked: true
        )
        let snapshotApple = try listSnapshot(for: apple, globalKey: "apple_maps:apple-map-item-1")
        let snapshotAMap = try listSnapshot(for: amap, globalKey: "amap:B0AMAP1")
        let first = try RestaurantListItem(
            id: stableUUID(61), remoteID: "list-item-z", ownerUserID: userID,
            listID: list.id, listRemoteID: "list-1", restaurantReferenceID: "restaurant-apple",
            localRestaurantID: apple.id, restaurantGlobalKey: snapshotApple.globalKey,
            restaurantSnapshot: snapshotApple, position: 0, note: "第一名"
        )
        let second = try RestaurantListItem(
            id: stableUUID(62), remoteID: "list-item-a", ownerUserID: userID,
            listID: list.id, listRemoteID: "list-1", restaurantReferenceID: "restaurant-amap",
            localRestaurantID: amap.id, restaurantGlobalKey: snapshotAMap.globalKey,
            restaurantSnapshot: snapshotAMap, position: 1, note: "第二名"
        )
        return BackupExportInput(
            restaurants: [manual, amap, apple], visits: [richVisit, nilVisit], dishes: [dish],
            visitDishes: [visitDish], photos: [photo], companions: [deletedCompanion, companion],
            recommendationSources: [source], profiles: [profile], restaurantLists: [list],
            restaurantListItems: [second, first]
        )
    }

    private func twoUserInput() throws -> BackupExportInput {
        let restaurantA = try ownedRestaurant(
            localID: stableUUID(101), remoteID: "restaurant-a", owner: userA,
            name: "A_PRIVATE_NAME", provider: .manual, externalID: "a-private"
        )
        let restaurantB = try ownedRestaurant(
            localID: stableUUID(102), remoteID: "restaurant-b", owner: userB,
            name: "B_PRIVATE_NAME", provider: .manual, externalID: "b-private"
        )
        return BackupExportInput(
            restaurants: [restaurantA, restaurantB],
            visits: [
                Visit(ownerUserID: userA, restaurantId: restaurantA.id, note: "A_PRIVATE_NOTE", remoteID: "visit-a"),
                Visit(ownerUserID: userB, restaurantId: restaurantB.id, note: "B_PRIVATE_NOTE", remoteID: "visit-b"),
            ],
            dishes: [], visitDishes: [], photos: [],
            companions: [
                DiningCompanion(ownerUserId: userA, displayName: "A_PRIVATE_COMPANION", remoteID: "companion-a"),
                DiningCompanion(ownerUserId: userB, displayName: "B_PRIVATE_COMPANION", remoteID: "companion-b"),
            ],
            recommendationSources: [],
            profiles: [UserProfile(tasteMapUserID: userA), UserProfile(tasteMapUserID: userB)],
            restaurantLists: [], restaurantListItems: []
        )
    }

    private func ownedRestaurant(
        localID: UUID,
        remoteID: String,
        owner: String,
        name: String,
        provider: RestaurantPlaceProvider,
        externalID: String
    ) throws -> Restaurant {
        let restaurant = Restaurant(
            id: localID,
            ownerUserID: owner,
            name: name,
            address: "杭州测试地址",
            latitude: 30.2,
            longitude: 120.1,
            appleMapItemIdentifier: provider == .appleMaps ? externalID : nil,
            city: "杭州",
            remoteID: remoteID,
            syncStatus: .synced
        )
        let timestamp = "2026-08-29T00:00:00.000Z"
        let record = try RestaurantJSONContractV1(
            id: remoteID,
            userId: owner,
            placeIdentities: [try RestaurantPlaceIdentityContract(
                provider: provider,
                externalId: externalID,
                isPrimary: true,
                createdAt: timestamp,
                updatedAt: timestamp
            )],
            amapPoiId: provider == .amap ? externalID : nil,
            name: name,
            address: restaurant.address,
            city: restaurant.city,
            latitude: restaurant.latitude,
            longitude: restaurant.longitude,
            status: .visited,
            preferenceLevel: .like,
            overallRating: 4.5,
            foodRating: 4.5,
            environmentRating: 4,
            serviceRating: 4.5,
            valueRating: 4,
            tags: ["寿司", "寿司", "日料"],
            longTermNote: "长期记录",
            pricePerPerson: 128.5,
            phone: nil,
            openingHours: nil,
            markerType: .emoji,
            markerPhotoId: nil,
            merchantImageUrl: "https://images.example.test/restaurant.jpg",
            markerEmoji: "🍣",
            createdAt: timestamp,
            updatedAt: timestamp,
            deletedAt: nil
        )
        restaurant.remoteRecordData = try JSONEncoder().encode(record)
        return restaurant
    }

    private func listSnapshot(for restaurant: Restaurant, globalKey: String) throws -> RestaurantListPlaceContractV1 {
        let record = try #require(restaurant.remoteRecordData.flatMap {
            try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0)
        })
        return try RestaurantListPlaceContractV1(
            globalKey: globalKey,
            restaurantId: record.id,
            placeIdentities: record.placeIdentities.map {
                RestaurantListPlaceIdentityContractV1(
                    provider: $0.provider, externalId: $0.externalId, isPrimary: $0.isPrimary
                )
            },
            name: restaurant.name,
            address: restaurant.address,
            city: restaurant.city,
            latitude: restaurant.latitude,
            longitude: restaurant.longitude,
            markerPhotoId: nil,
            merchantImageUrl: record.merchantImageUrl,
            markerEmoji: record.markerEmoji
        )
    }

    private func stableUUID(_ value: Int) -> UUID {
        let tail = String(format: "%012x", value)
        return UUID(uuidString: "00000000-0000-4000-8000-\(tail)")!
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

@MainActor
private struct Harness {
    let container: ModelContainer
    let context: ModelContext
    let service: BackupExportService
}
