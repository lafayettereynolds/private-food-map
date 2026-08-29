import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("F1-C3 backup import merge engine", .serialized)
@MainActor
struct BackupImportMergeEngineTests {
    private let userID = "tm_f1c3_user"

    @Test("Apple, AMap and multi-provider identities match deterministically")
    func exactRestaurantIdentity() throws {
        let apple = localRestaurant(provider: "apple_maps", externalID: "apple-1")
        let amap = localRestaurant(provider: "amap", externalID: "amap-1", localID: fixedUUID("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"))
        let local = snapshot(restaurants: [apple, amap])
        let graph = baseGraph().with(restaurants: [
            restaurant("r-apple", identities: [identity("apple_maps", "apple-1", true)]),
            restaurant("r-amap", identities: [identity("amap", "amap-1", true)]),
            restaurant("r-multi", identities: [identity("apple_maps", "apple-1", true), identity("amap", "amap-2", false)]),
        ], visits: [])
        let first = try BackupImportPlanEngine().makePlan(source: graph, local: local)
        let second = try BackupImportPlanEngine().makePlan(source: graph, local: local, generatedAt: .distantFuture)
        #expect(first == second)
        #expect(first.actions.allSatisfy { $0.action == .exactMerge })
    }

    @Test("Cross-provider probable Restaurant supports merge, create and skip without guessing")
    func probableRestaurantReview() throws {
        let graph = baseGraph().with(restaurants: [restaurant(
            "source", name: "同一家店", address: "商场一楼", city: "上海",
            latitude: 31.2, longitude: 121.5,
            identities: [identity("apple_maps", "apple-source", true)]
        )], visits: [])
        let candidate = localRestaurant(
            provider: "amap", externalID: "amap-local", name: "同一家店",
            address: "商场一楼", city: "上海", latitude: 31.20001, longitude: 121.5
        )
        let local = snapshot(restaurants: [candidate])
        let initial = try BackupImportPlanEngine().makePlan(source: graph, local: local)
        let review = try #require(initial.reviewItems.first)
        #expect(initial.actions.first?.action == .userReviewRequired)
        for (optionID, expected) in [("merge", BackupImportPlanActionKind.exactMerge), ("create", .create), ("skip", .skip)] {
            let option = try #require(review.options.first { $0.id == optionID })
            let plan = try BackupImportPlanEngine().makePlan(
                source: graph, local: local,
                decisions: [decision(review, option: option, graph: graph, local: local)]
            )
            #expect(plan.actions.first?.action == expected)
            #expect(plan.reviewItems.isEmpty)
        }
    }

    @Test("Ambiguous branches create new and a local tombstone prevents revival")
    func branchAndTombstone() throws {
        let one = localRestaurant(provider: "manual", externalID: "one", name: "连锁店", address: "", city: "上海", latitude: 0, longitude: 0)
        let two = localRestaurant(provider: "manual", externalID: "two", name: "连锁店", address: "", city: "上海", latitude: 0, longitude: 0, localID: fixedUUID("cccccccc-cccc-4ccc-8ccc-cccccccccccc"))
        var graph = baseGraph().with(restaurants: [restaurant("branch", name: "连锁店", address: "", city: "上海", latitude: 0, longitude: 0, identities: [])], visits: [])
        var plan = try BackupImportPlanEngine().makePlan(source: graph, local: snapshot(restaurants: [one, two]))
        #expect(plan.actions.first?.reasonCode == "ambiguousChainOrBranchCreateNew")
        let deleted = localRestaurant(provider: "apple_maps", externalID: "dead", deletedAt: .now)
        graph = baseGraph().with(restaurants: [restaurant("dead", identities: [identity("apple_maps", "dead", true)])], visits: [])
        plan = try BackupImportPlanEngine().makePlan(source: graph, local: snapshot(restaurants: [deleted]))
        #expect(plan.actions.first?.reasonCode == "skipBecauseTombstoned")
    }

    @Test("Visit fingerprint handles nil, repeat dates, collisions and tombstones")
    func visitIdentity() throws {
        let ownerRestaurant = localRestaurant(provider: "apple_maps", externalID: "apple-1")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let duplicate = localVisit("existing", restaurantID: ownerRestaurant.remoteID, date: date, note: nil)
        let collision = localVisit("collision", restaurantID: ownerRestaurant.remoteID, note: "本地")
        let tombstone = localVisit("deleted", restaurantID: ownerRestaurant.remoteID, deletedAt: .now)
        let graph = baseGraph().with(
            restaurants: [restaurant("r", identities: [identity("apple_maps", "apple-1", true)])],
            visits: [visit("same", restaurantID: "r", date: date), visit("different", restaurantID: "r", date: date, note: "第二次"), visit("collision", restaurantID: "r", note: "备份"), visit("deleted", restaurantID: "r")]
        )
        let plan = try BackupImportPlanEngine().makePlan(source: graph, local: snapshot(restaurants: [ownerRestaurant], visits: [duplicate, collision, tombstone]))
        #expect(plan.actions.first { $0.sourceID == "same" }?.action == .exactDuplicate)
        #expect(plan.actions.first { $0.sourceID == "different" }?.action == .create)
        #expect(plan.actions.first { $0.sourceID == "collision" }?.action == .userReviewRequired)
        #expect(plan.actions.first { $0.sourceID == "deleted" }?.reasonCode == "skipBecauseTombstoned")
    }

    @Test("Dish, VisitDish, private directories, photos, profile and lists follow conservative policies")
    func richEntityPolicies() throws {
        let graph = baseGraph()
        let plan = try BackupImportPlanEngine().makePlan(source: graph, local: snapshot())
        #expect(plan.actions.first { $0.entityType == .dish }?.action == .create)
        #expect(plan.actions.first { $0.entityType == .visitDish }?.dependencySourceIDs.count == 3)
        #expect(plan.actions.first { $0.entityType == .photo }?.action == .skip)
        #expect(plan.warnings.contains { $0.contains("照片") })
        #expect(plan.actions.first { $0.entityType == .restaurantList }?.action == .create)
        #expect(plan.actions.first { $0.entityType == .restaurantListItem }?.action == .create)

        let localCompanion = BackupImportLocalRecord(localID: UUID(), remoteID: "lc", deletedAt: nil, value: companion("lc", "Alice"))
        let localSource = BackupImportLocalRecord(localID: UUID(), remoteID: "ls", deletedAt: nil, value: recommendation("ls", "小红书", "xiaohongshu"))
        let directoryGraph = graph.withDirectories([companion("bc", "  Alice ")], [recommendation("bs", "小红书", "xiaohongshu")])
        let directoryPlan = try BackupImportPlanEngine().makePlan(source: directoryGraph, local: snapshot(companions: [localCompanion], sources: [localSource]))
        #expect(directoryPlan.actions.allSatisfy { $0.action == .exactMerge })

        let localProfile = BackupImportSourceProfile(sourceID: "lp", displayName: "当前名字", bio: "", city: "上海", avatarPhotoSourceID: nil, avatarPresetID: "polar-bear", visibility: "private", createdAt: .distantPast, updatedAt: .distantPast)
        let profilePlan = try BackupImportPlanEngine().makePlan(source: graph.withOnlyProfile(), local: snapshot(profiles: [BackupImportLocalRecord(localID: UUID(), remoteID: "lp", deletedAt: nil, value: localProfile)]))
        #expect(profilePlan.reviewItems.contains { $0.id.contains("displayName") })
        #expect(profilePlan.actions.first?.action == .userReviewRequired)
    }

    @Test("Snapshot fails closed on ambiguous owner and excludes another Taste Map user")
    func currentUserIsolation() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let ambiguous = Restaurant(name: "Ambiguous", address: "", latitude: 0, longitude: 0)
        container.mainContext.insert(ambiguous)
        #expect(throws: BackupImportPlanningError.self) {
            try BackupImportLocalSnapshotBuilder(context: container.mainContext).make(currentTasteMapUserID: userID)
        }
        container.mainContext.delete(ambiguous)
        container.mainContext.insert(try ownedRestaurant(userID: "tm_other_user", id: UUID()))
        try container.mainContext.save()
        let snapshot = try BackupImportLocalSnapshotBuilder(context: container.mainContext).make(currentTasteMapUserID: userID)
        #expect(snapshot.restaurants.isEmpty)
    }

    @Test("Atomic success creates the complete offline graph and current SyncMutations")
    func atomicSuccess() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let confirmed = try confirmedPlan(container)
        let result = try BackupImportTransactionWriter(container: container).execute(confirmed, currentTasteMapUserID: userID)
        #expect(result.writtenEntityCount == 10)
        #expect(result.queuedMutationCount == 10)
        let observer = ModelContext(container)
        #expect(try observer.fetchCount(FetchDescriptor<Restaurant>()) == 1)
        #expect(try observer.fetchCount(FetchDescriptor<Visit>()) == 1)
        #expect(try observer.fetchCount(FetchDescriptor<Dish>()) == 1)
        #expect(try observer.fetchCount(FetchDescriptor<VisitDish>()) == 1)
        #expect(try observer.fetchCount(FetchDescriptor<PhotoAsset>()) == 0)
        let mutations = try observer.fetch(FetchDescriptor<SyncMutation>())
        #expect(mutations.count == 10)
        #expect(mutations.allSatisfy { $0.baseVersion == 0 && $0.state == .queued })
        #expect(Set(mutations.map(\.entityType)).isSuperset(of: [.restaurant, .visit, .dish, .visitDish]))
        let companion = try #require(observer.fetch(FetchDescriptor<DiningCompanion>()).first)
        let source = try #require(observer.fetch(FetchDescriptor<RecommendationSource>()).first)
        let importedDish = try #require(observer.fetch(FetchDescriptor<Dish>()).first)
        let importedProfile = try #require(observer.fetch(FetchDescriptor<UserProfile>()).first)
        let importedList = try #require(observer.fetch(FetchDescriptor<RestaurantList>()).first)
        #expect(companion.ownerUserId == userID && companion.linkedTasteMapUserId == nil)
        #expect(source.ownerUserId == userID && source.linkedTasteMapUserId == nil)
        #expect(importedDish.photoRemoteID == nil)
        #expect(importedProfile.tasteMapUserID == userID && importedProfile.avatarPhotoID == nil)
        #expect(importedList.ownerUserID == userID && importedList.customCoverPhotoID == nil)
        #expect(try observer.fetch(FetchDescriptor<RestaurantListItem>()).map(\.position).sorted() == [0, 1])
    }

    @Test(arguments: [BackupImportFailurePoint.afterRestaurants, .afterVisits, .beforeMutations, .beforeSave])
    func injectedFailureIsAtomic(point: BackupImportFailurePoint) throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let confirmed = try confirmedPlan(container)
        #expect(throws: BackupImportPlanningError.self) {
            try BackupImportTransactionWriter(container: container, injectedFailurePoint: point).execute(confirmed, currentTasteMapUserID: userID)
        }
        let observer = ModelContext(container)
        #expect(try observer.fetchCount(FetchDescriptor<Restaurant>()) == 0)
        #expect(try observer.fetchCount(FetchDescriptor<Visit>()) == 0)
        #expect(try observer.fetchCount(FetchDescriptor<SyncMutation>()) == 0)
    }

    @Test("Real read-only save failure rolls back without SQLite lifetime warnings")
    func realSaveFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("F1C3-NoSave-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("TasteMap.store")
        let confirmed: ConfirmedBackupImportPlan
        do { confirmed = try confirmedPlan(TasteMapPersistence.makeContainer(storageURL: storeURL)) }
        do {
            let config = ModelConfiguration("F1C3-NoSave", schema: TasteMapPersistence.schema, url: storeURL, allowsSave: false, cloudKitDatabase: .none)
            let readOnly = try ModelContainer(for: TasteMapPersistence.schema, configurations: [config])
            #expect(throws: Error.self) {
                try BackupImportTransactionWriter(container: readOnly).execute(confirmed, currentTasteMapUserID: userID)
            }
        }
        do {
            let observer = try TasteMapPersistence.makeContainer(storageURL: storeURL)
            #expect(try observer.mainContext.fetchCount(FetchDescriptor<Restaurant>()) == 0)
            #expect(try observer.mainContext.fetchCount(FetchDescriptor<SyncMutation>()) == 0)
        }
        try FileManager.default.removeItem(at: directory)
    }

    @Test("Offline transaction survives restart; stale, repeated and switched-user execution are rejected")
    func restartAndGuards() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("F1C3-Restart-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("TasteMap.store")
        let confirmed: ConfirmedBackupImportPlan
        do {
            let container = try TasteMapPersistence.makeContainer(storageURL: storeURL)
            confirmed = try confirmedPlan(container)
            _ = try BackupImportTransactionWriter(container: container).execute(confirmed, currentTasteMapUserID: userID)
            #expect(throws: BackupImportPlanningError.self) { try BackupImportTransactionWriter(container: container).execute(confirmed, currentTasteMapUserID: userID) }
            #expect(throws: BackupImportPlanningError.self) { try BackupImportTransactionWriter(container: container).execute(confirmed, currentTasteMapUserID: "tm_switched") }
        }
        do {
            let restarted = try TasteMapPersistence.makeContainer(storageURL: storeURL)
            let restaurants = try restarted.mainContext.fetch(FetchDescriptor<Restaurant>())
            let visits = try restarted.mainContext.fetch(FetchDescriptor<Visit>())
            #expect(restaurants.count == 1 && visits.count == 1)
            #expect(visits.first?.restaurantId == restaurants.first?.id)
            #expect(try restarted.mainContext.fetchCount(FetchDescriptor<SyncMutation>()) == 10)
        }
        try FileManager.default.removeItem(at: directory)
    }

    @Test("Planner handles 1,000 Restaurants, 10,000 Visits and 5,000 Dishes with indexed matching")
    func largeDataset() throws {
        let restaurants = (0..<1_000).map { restaurant("r-\($0)", name: "餐厅 \($0)", identities: [identity("apple_maps", "apple-\($0)", true)]) }
        let visits = (0..<10_000).map { visit("v-\($0)", restaurantID: "r-\($0 % 1_000)", date: Date(timeIntervalSince1970: Double(1_700_000_000 + $0))) }
        let dishes = (0..<5_000).map { dish("d-\($0)", restaurantID: "r-\($0 % 1_000)", visitID: "v-\($0)") }
        let graph = baseGraph().with(restaurants: restaurants, visits: visits, dishes: dishes)
        let start = ContinuousClock.now
        let plan = try BackupImportPlanEngine().makePlan(source: graph, local: snapshot())
        #expect(plan.actions.count == 16_000)
        #expect(start.duration(to: .now) < .seconds(15))
    }

    @Test("One atomic persistent transaction handles 200 Restaurants and 2,000 Visits")
    func mediumTransactionPerformance() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("F1C3-Performance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("TasteMap.store")
        do {
            let container = try TasteMapPersistence.makeContainer(storageURL: storeURL)
            let restaurants = (0..<200).map { restaurant("r-\($0)", name: "导入餐厅 \($0)", identities: [identity("apple_maps", "perf-apple-\($0)", true)]) }
            let visits = (0..<2_000).map { visit("v-\($0)", restaurantID: "r-\($0 % 200)", date: Date(timeIntervalSince1970: Double(1_700_000_000 + $0))) }
            let graph = baseGraph().with(restaurants: restaurants, visits: visits)
            let local = try BackupImportLocalSnapshotBuilder(context: container.mainContext).make(currentTasteMapUserID: userID)
            let plan = try BackupImportPlanEngine().makePlan(source: graph, local: local)
            let result = try BackupImportTransactionWriter(container: container).execute(
                ConfirmedBackupImportPlan(plan: plan, sourceGraph: graph, decisions: []),
                currentTasteMapUserID: userID
            )
            #expect(result.writtenEntityCount == 2_200)
            #expect(result.queuedMutationCount == 2_200)
            #expect(result.transactionSeconds < 30)
        }
        try FileManager.default.removeItem(at: directory)
    }

    // MARK: fixtures

    private func confirmedPlan(_ container: ModelContainer) throws -> ConfirmedBackupImportPlan {
        let graph = baseGraph()
        let local = try BackupImportLocalSnapshotBuilder(context: container.mainContext).make(currentTasteMapUserID: userID)
        let plan = try BackupImportPlanEngine().makePlan(source: graph, local: local)
        #expect(plan.canBeConfirmed)
        return ConfirmedBackupImportPlan(plan: plan, sourceGraph: graph, decisions: [])
    }

    private func snapshot(
        restaurants: [BackupImportLocalRecord<BackupImportSourceRestaurant>] = [],
        visits: [BackupImportLocalRecord<BackupImportSourceVisit>] = [],
        companions: [BackupImportLocalRecord<BackupImportSourceCompanion>] = [],
        sources: [BackupImportLocalRecord<BackupImportSourceRecommendationSource>] = [],
        profiles: [BackupImportLocalRecord<BackupImportSourceProfile>] = []
    ) -> BackupImportLocalSnapshot {
        BackupImportLocalSnapshot(currentTasteMapUserID: userID, revision: String(repeating: "f", count: 64), restaurants: restaurants, visits: visits, dishes: [], visitDishes: [], photos: [], companions: companions, recommendationSources: sources, profiles: profiles, restaurantLists: [], restaurantListItems: [])
    }

    private func baseGraph() -> BackupImportSourceGraph {
        let r = restaurant("r-1", identities: [identity("apple_maps", "apple-r-1", true)])
        let v0 = visit("v-1", restaurantID: r.sourceID)
        let c = companion("c-1", "Alice")
        let s = recommendation("s-1", "小红书", "xiaohongshu")
        let v = visit("v-1", restaurantID: r.sourceID, companionIDs: [c.sourceID], recommendationID: s.sourceID)
        let d = dish("d-1", restaurantID: r.sourceID, visitID: v0.sourceID)
        let profile = BackupImportSourceProfile(sourceID: "p-1", displayName: "备份用户", bio: "喜欢探索餐厅", city: "杭州", avatarPhotoSourceID: "photo-avatar", avatarPresetID: "cat", visibility: "private", createdAt: .distantPast, updatedAt: .distantPast)
        let list = BackupImportSourceRestaurantList(sourceID: "l-1", title: "我的榜单", listDescription: "备份榜单", visibility: "private", isRanked: true, coverMode: "custom", customCoverPhotoSourceID: "photo-1", createdAt: .distantPast, updatedAt: .distantPast)
        return BackupImportSourceGraph(
            sourceFileSHA256: String(repeating: "b", count: 64), sourceFormat: .backupV1,
            restaurants: [r], visits: [v], dishes: [d],
            visitDishes: [BackupImportSourceVisitDish(sourceID: "vd-1", sourceRestaurantID: r.sourceID, sourceVisitID: v.sourceID, sourceDishID: d.sourceID, sortOrder: 0, createdAt: .distantPast, updatedAt: .distantPast)],
            photos: [BackupImportSourcePhoto(sourceID: "photo-1", parentEntityType: "restaurant", parentSourceID: r.sourceID, kind: "restaurant-marker", fileName: "missing.jpg", mimeType: "image/jpeg", byteSize: 123, width: 100, height: 100, sortOrder: 0, visibility: "private", createdAt: .distantPast, updatedAt: .distantPast, binaryAvailable: false)],
            companions: [c], recommendationSources: [s], profiles: [profile], restaurantLists: [list],
            restaurantListItems: [
                BackupImportSourceRestaurantListItem(sourceID: "li-1", sourceListID: list.sourceID, sourceRestaurantID: r.sourceID, position: 0, note: "第一名", createdAt: .distantPast, updatedAt: .distantPast),
                BackupImportSourceRestaurantListItem(sourceID: "li-2", sourceListID: list.sourceID, sourceRestaurantID: r.sourceID, position: 1, note: "第二名", createdAt: .distantPast, updatedAt: .distantPast),
            ], tombstones: []
        )
    }

    private func restaurant(_ id: String, name: String = "测试餐厅", address: String = "测试路 1 号", city: String = "上海", latitude: Double = 31.2, longitude: Double = 121.5, identities: [BackupImportSourcePlaceIdentity]) -> BackupImportSourceRestaurant {
        BackupImportSourceRestaurant(sourceID: id, placeIdentities: identities, name: name, address: address, city: city, latitude: latitude, longitude: longitude, status: "visited", preferenceLevel: "like", overallRating: nil, foodRating: nil, environmentRating: nil, serviceRating: nil, valueRating: nil, tags: ["测试"], longTermNote: "", pricePerPerson: nil, phone: nil, openingHours: nil, markerType: "emoji", markerPhotoSourceID: nil, merchantImageURL: nil, markerEmoji: "🍜", createdAt: .distantPast, updatedAt: .distantPast)
    }

    private func visit(_ id: String, restaurantID: String, date: Date = Date(timeIntervalSince1970: 1_700_000_000), note: String? = nil, companionIDs: [String] = [], recommendationID: String? = nil) -> BackupImportSourceVisit {
        BackupImportSourceVisit(sourceID: id, sourceRestaurantID: restaurantID, visitedAt: date, diningMode: "dine_in", visibility: "private", partySize: nil, totalPrice: nil, myActualSpend: nil, paymentMode: nil, pricePerPerson: nil, queueDuration: nil, diningOccasions: [], diningOccasionText: nil, rating: nil, valueRating: nil, environmentRating: nil, serviceRating: nil, valueTags: [], environmentTags: [], serviceTags: [], noiseLevel: nil, diningDuration: nil, portionLevel: nil, transportConvenience: nil, specialNotes: nil, companionSourceIDs: companionIDs, recommendationSourceID: recommendationID, recommendationSourceType: recommendationID == nil ? nil : "xiaohongshu", recommendationSourceText: nil, note: note, createdAt: .distantPast, updatedAt: .distantPast)
    }

    private func dish(_ id: String, restaurantID: String, visitID: String) -> BackupImportSourceDish {
        BackupImportSourceDish(sourceID: id, sourceRestaurantID: restaurantID, sourceVisitID: visitID, name: "招牌菜", taste: "香", rating: 4.5, price: 38, sourcePhotoID: "photo-1", sortOrder: 0, createdAt: .distantPast, updatedAt: .distantPast)
    }

    private func companion(_ id: String, _ name: String) -> BackupImportSourceCompanion { BackupImportSourceCompanion(sourceID: id, displayName: name, createdAt: .distantPast, updatedAt: .distantPast) }
    private func recommendation(_ id: String, _ name: String, _ type: String) -> BackupImportSourceRecommendationSource { BackupImportSourceRecommendationSource(sourceID: id, displayName: name, sourceType: type, createdAt: .distantPast, updatedAt: .distantPast) }
    private func identity(_ provider: String, _ id: String, _ primary: Bool) -> BackupImportSourcePlaceIdentity { BackupImportSourcePlaceIdentity(provider: provider, externalID: id, isPrimary: primary) }
    private func fixedUUID(_ value: String) -> UUID { UUID(uuidString: value)! }

    private func localRestaurant(provider: String, externalID: String, name: String = "本地餐厅", address: String = "本地地址", city: String = "上海", latitude: Double = 31.1, longitude: Double = 121.4, localID: UUID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!, deletedAt: Date? = nil) -> BackupImportLocalRecord<BackupImportSourceRestaurant> {
        let value = restaurant("local-\(externalID)", name: name, address: address, city: city, latitude: latitude, longitude: longitude, identities: [identity(provider, externalID, true)])
        return BackupImportLocalRecord(localID: localID, remoteID: value.sourceID, deletedAt: deletedAt, value: value)
    }

    private func localVisit(_ id: String, restaurantID: String, date: Date = Date(timeIntervalSince1970: 1_700_000_000), note: String? = nil, deletedAt: Date? = nil) -> BackupImportLocalRecord<BackupImportSourceVisit> {
        BackupImportLocalRecord(localID: UUID(), remoteID: id, deletedAt: deletedAt, value: visit(id, restaurantID: restaurantID, date: date, note: note))
    }

    private func decision(_ item: ImportPlanReviewItem, option: BackupImportReviewOption, graph: BackupImportSourceGraph, local: BackupImportLocalSnapshot) -> BackupImportReviewDecision {
        BackupImportReviewDecision(reviewItemID: item.id, selectedOptionID: option.id, sourceFileSHA256: graph.sourceFileSHA256, sourceID: item.sourceID, targetID: option.targetID, localSnapshotRevision: local.revision)
    }

    private func ownedRestaurant(userID: String, id: UUID) throws -> Restaurant {
        let place = try RestaurantPlaceIdentityContract(provider: .manual, externalId: "tastemap:\(id.uuidString)", isPrimary: true, createdAt: SyncRecordMapper.dateString(.distantPast), updatedAt: SyncRecordMapper.dateString(.distantPast))
        let contract = try RestaurantJSONContractV1(id: id.uuidString.lowercased(), userId: userID, placeIdentities: [place], name: "Owned", address: "", city: "", latitude: 0, longitude: 0, status: .visited, preferenceLevel: .normal, overallRating: nil, foodRating: nil, environmentRating: nil, serviceRating: nil, valueRating: nil, tags: [], longTermNote: "", pricePerPerson: nil, phone: nil, openingHours: nil, markerType: .emoji, markerPhotoId: nil, merchantImageUrl: nil, markerEmoji: "🍽️", createdAt: SyncRecordMapper.dateString(.distantPast), updatedAt: SyncRecordMapper.dateString(.distantPast), deletedAt: nil)
        return Restaurant(id: id, name: "Owned", address: "", latitude: 0, longitude: 0, remoteID: id.uuidString.lowercased(), remoteRecordData: try JSONEncoder().encode(contract))
    }
}

private extension BackupImportSourceGraph {
    func with(restaurants: [BackupImportSourceRestaurant], visits: [BackupImportSourceVisit], dishes: [BackupImportSourceDish] = []) -> Self {
        BackupImportSourceGraph(sourceFileSHA256: sourceFileSHA256, sourceFormat: sourceFormat, restaurants: restaurants, visits: visits, dishes: dishes, visitDishes: [], photos: [], companions: [], recommendationSources: [], profiles: [], restaurantLists: [], restaurantListItems: [], tombstones: [])
    }
    func withDirectories(_ companions: [BackupImportSourceCompanion], _ sources: [BackupImportSourceRecommendationSource]) -> Self {
        BackupImportSourceGraph(sourceFileSHA256: sourceFileSHA256, sourceFormat: sourceFormat, restaurants: [], visits: [], dishes: [], visitDishes: [], photos: [], companions: companions, recommendationSources: sources, profiles: [], restaurantLists: [], restaurantListItems: [], tombstones: [])
    }
    func withOnlyProfile() -> Self {
        BackupImportSourceGraph(sourceFileSHA256: sourceFileSHA256, sourceFormat: sourceFormat, restaurants: [], visits: [], dishes: [], visitDishes: [], photos: [], companions: [], recommendationSources: [], profiles: profiles, restaurantLists: [], restaurantListItems: [], tombstones: [])
    }
}
