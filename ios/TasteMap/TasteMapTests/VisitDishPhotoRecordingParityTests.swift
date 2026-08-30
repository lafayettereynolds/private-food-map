import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("Task 04 Visit, Dish, Photo recording parity", .serialized)
@MainActor
struct VisitDishPhotoRecordingParityTests {
    @Test("Submission gate admits one save until the current save finishes")
    func submissionIsSingleFlight() {
        var gate = VisitSubmissionGate()
        let firstBegin = gate.begin()
        let overlappingBegin = gate.begin()
        #expect(firstBegin)
        #expect(!overlappingBegin)
        #expect(gate.isSubmitting)
        gate.finish()
        #expect(!gate.isSubmitting)
        let beginAfterFinish = gate.begin()
        #expect(beginAfterFinish)
    }

    @Test("One transaction records the full Visit matrix, directories, Dishes, and mutations")
    func fullMealGraphCommit() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = Restaurant(
            ownerUserID: "tm_task04_owner",
            name: "Task 04 Apple 餐厅",
            address: "Apple Maps only",
            latitude: 30.25,
            longitude: 120.16,
            appleMapItemIdentifier: "apple-task04"
        )
        context.insert(restaurant)
        try context.save()
        let visitedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let firstDishID = UUID()
        let result = try LocalVisitRecordingStore(context: context).commit(
            restaurant: restaurant,
            candidate: nil,
            existingVisit: nil,
            allRestaurants: [restaurant],
            draft: VisitDraft(
                visitedAt: visitedAt,
                diningMode: .dineIn,
                partySize: 3,
                rating: 4.5,
                valueRating: 4,
                environmentRating: 5,
                serviceRating: 3.5,
                myActualSpend: 128,
                totalPrice: 384,
                visibility: .friends,
                paymentMode: .aa,
                queueDuration: .under60,
                diningOccasions: [.friends, .celebration],
                diningOccasionText: "生日聚餐",
                valueTags: ["合理"],
                environmentTags: ["安静"],
                serviceTags: ["周到"],
                noiseLevel: .normal,
                diningDuration: .under30,
                portionLevel: .generous,
                transportConvenience: .veryConvenient,
                specialNotes: "靠窗位",
                companionNames: ["小王", "妈妈"],
                recommendationSourceType: .blogger,
                recommendationSourceText: "某美食博主",
                note: "完整到访记录"
            ),
            dishDrafts: [
                DishDraft(id: firstDishID, name: "招牌牛肉", taste: "值得再点", rating: 5, price: 88),
                DishDraft(name: "时蔬", rating: nil, price: nil),
            ],
            actorUserID: "tm_task04_owner"
        )

        #expect(result.visit.visitedAt == visitedAt)
        #expect(result.visit.rating == 4.5)
        #expect(result.visit.valueRating == 4)
        #expect(result.visit.environmentRating == 5)
        #expect(result.visit.serviceRating == 3.5)
        #expect(result.visit.myActualSpend == 128)
        #expect(result.visit.totalPrice == 384)
        #expect(result.visit.pricePerPerson == 128)
        #expect(result.visit.paymentMode == .aa)
        #expect(result.visit.queueDuration == .under60)
        #expect(result.visit.diningOccasions == [.friends, .celebration])
        #expect(result.visit.specialNotes == "靠窗位")
        #expect(result.visit.companionNames == ["小王", "妈妈"])
        #expect(result.visit.recommendationSourceText == "某美食博主")
        #expect(result.visit.visibility == .friends)
        #expect(result.dishesByDraftID[firstDishID]?.name == "招牌牛肉")
        #expect(try context.fetch(FetchDescriptor<Visit>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Dish>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<VisitDish>()).filter { $0.deletedAt == nil }.count == 2)
        #expect(try context.fetch(FetchDescriptor<DiningCompanion>()).allSatisfy {
            $0.ownerUserId == "tm_task04_owner"
        })
        #expect(try context.fetch(FetchDescriptor<RecommendationSource>()).allSatisfy {
            $0.ownerUserId == "tm_task04_owner"
        })

        let mutations = try context.fetch(FetchDescriptor<SyncMutation>())
        for type in [
            SyncEntityType.visit, .dish, .visitDish, .companion, .recommendationSource,
        ] {
            #expect(mutations.contains { $0.entityType == type })
        }
    }

    @Test("Invalid child data is rejected before any partial Visit graph is written")
    func rollbackLeavesNoPartialGraph() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = Restaurant(
            ownerUserID: "tm_owner",
            name: "Rollback 餐厅", address: "杭州", latitude: 30, longitude: 120
        )
        context.insert(restaurant)
        try context.save()
        let recorder = LocalVisitRecordingStore(context: context)

        #expect(throws: DishDraftError.missingName) {
            _ = try recorder.commit(
                restaurant: restaurant,
                candidate: nil,
                existingVisit: nil,
                allRestaurants: [restaurant],
                draft: VisitDraft(companionNames: ["不应写入"]),
                dishDrafts: [DishDraft(name: "   ")],
                actorUserID: "tm_owner"
            )
        }
        #expect(try context.fetch(FetchDescriptor<Visit>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DiningCompanion>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).isEmpty)
    }

    @Test("Private companion and source names never merge across Taste Map users")
    func privateDirectoriesAreOwnerScoped() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let store = LocalCompanionSourceStore(context: context)
        let companionA = try store.findOrCreateCompanion(name: "小王", ownerUserID: "tm_user_a")
        let companionB = try store.findOrCreateCompanion(name: "小王", ownerUserID: "tm_user_b")
        let sourceA = try store.findOrCreateRecommendationSource(
            name: "朋友推荐", type: .friend, ownerUserID: "tm_user_a"
        )
        let sourceB = try store.findOrCreateRecommendationSource(
            name: "朋友推荐", type: .friend, ownerUserID: "tm_user_b"
        )
        try context.save()

        #expect(companionA.id != companionB.id)
        #expect(sourceA.id != sourceB.id)
        #expect(companionA.linkedTasteMapUserId == nil)
        #expect(companionB.linkedTasteMapUserId == nil)
        #expect(try context.fetch(FetchDescriptor<DiningCompanion>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<RecommendationSource>()).count == 2)
    }

    @Test("Restaurant gallery keeps Dish-linked photos from active Visits")
    func dishLinkedPhotoRemainsVisibleInRestaurantGallery() {
        let restaurantID = UUID()
        let activeVisitID = UUID()
        let deletedVisitID = UUID()
        let dishPhoto = PhotoAsset(
            restaurantId: restaurantID,
            visitId: activeVisitID,
            dishId: UUID(),
            kind: .dish,
            mimeType: "image/jpeg",
            byteSize: 10
        )
        let deletedVisitPhoto = PhotoAsset(
            restaurantId: restaurantID,
            visitId: deletedVisitID,
            kind: .visit,
            mimeType: "image/jpeg",
            byteSize: 10
        )
        let binaryDeleted = PhotoAsset(
            restaurantId: restaurantID,
            visitId: activeVisitID,
            kind: .dish,
            mimeType: "image/jpeg",
            byteSize: 10,
            binaryDeletedAt: .now
        )
        let visible = RestaurantDetailImageResolver.visibleRestaurantPhotos(
            [dishPhoto, deletedVisitPhoto, binaryDeleted],
            restaurantID: restaurantID,
            activeVisitIDs: [activeVisitID]
        )

        #expect(visible.map(\.id) == [dishPhoto.id])
    }

    @Test("An actor cannot record a Visit against another synced owner's Restaurant")
    func restaurantOwnershipIsEnforced() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = Restaurant(
            ownerUserID: "tm_user_a",
            name: "Owner A 餐厅", address: "杭州", latitude: 30, longitude: 120,
            appleMapItemIdentifier: "apple-owner-a"
        )
        context.insert(restaurant)
        var object = try #require(
            JSONSerialization.jsonObject(with: SyncRecordMapper.restaurantPayload(restaurant)) as? [String: Any]
        )
        object["userId"] = "tm_user_a"
        restaurant.remoteRecordData = try JSONSerialization.data(withJSONObject: object)
        try context.save()

        #expect(throws: LocalTasteMapStoreError.self) {
            _ = try LocalVisitRecordingStore(context: context).commit(
                restaurant: restaurant,
                candidate: nil,
                existingVisit: nil,
                allRestaurants: [restaurant],
                draft: VisitDraft(),
                dishDrafts: [],
                actorUserID: "tm_user_b"
            )
        }
        #expect(try context.fetch(FetchDescriptor<Visit>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).isEmpty)
    }

    @Test("Frequent Restaurant dishes sort before merely recent dishes and ignore deleted history")
    func restaurantDishReuseOrder() {
        let restaurantID = UUID()
        let otherRestaurantID = UUID()
        let frequent = Dish(restaurantId: restaurantID, visitId: UUID(), name: "常点菜")
        let recent = Dish(restaurantId: restaurantID, visitId: UUID(), name: "近期菜")
        let deleted = Dish(
            restaurantId: restaurantID, visitId: UUID(), name: "已删除菜", deletedAt: .now
        )
        let other = Dish(restaurantId: otherRestaurantID, visitId: UUID(), name: "别家菜")
        let oldVisit = Visit(
            restaurantId: restaurantID,
            visitedAt: Date(timeIntervalSince1970: 100)
        )
        let middleVisit = Visit(
            restaurantId: restaurantID,
            visitedAt: Date(timeIntervalSince1970: 200)
        )
        let recentVisit = Visit(
            restaurantId: restaurantID,
            visitedAt: Date(timeIntervalSince1970: 300)
        )
        let associations = [
            VisitDish(restaurantId: restaurantID, visitId: oldVisit.id, dishId: frequent.id),
            VisitDish(restaurantId: restaurantID, visitId: middleVisit.id, dishId: frequent.id),
            VisitDish(restaurantId: restaurantID, visitId: recentVisit.id, dishId: recent.id),
            VisitDish(
                restaurantId: restaurantID, visitId: recentVisit.id, dishId: deleted.id
            ),
        ]
        let usage = DishReuseResolver.usage(
            restaurantID: restaurantID,
            dishes: [frequent, recent, deleted, other],
            associations: associations,
            visits: [oldVisit, middleVisit, recentVisit]
        )
        let ordered = DishReuseResolver.orderedUniqueDishes(
            restaurantID: restaurantID,
            dishes: [recent, other, deleted, frequent],
            usageByDishID: usage
        )

        #expect(usage[frequent.id]?.count == 2)
        #expect(usage[recent.id]?.count == 1)
        #expect(ordered.map(\.id) == [frequent.id, recent.id])
    }
}
