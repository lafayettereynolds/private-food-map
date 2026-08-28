import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("P2-G rich Visit hardening", .serialized)
@MainActor
struct P2GHardeningTests {
    @Test("Legacy compact edit changes only its four fields and preserves the full P2 record")
    func compactEditPreservesRichVisit() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = Restaurant(
            name: "P2-G 完整记录餐厅",
            address: "Apple Maps only",
            latitude: 30.25,
            longitude: 120.16,
            appleMapItemIdentifier: "apple-p2g-rich-visit",
            remoteID: "p2g-restaurant-\(UUID().uuidString.lowercased())"
        )
        context.insert(restaurant)
        try context.save()
        let store = LocalTasteMapStore(context: context)
        let visit = try store.createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(
                diningMode: .dineIn,
                partySize: 3,
                rating: 4.5,
                valueRating: 5,
                environmentRating: 4,
                serviceRating: 3.5,
                myActualSpend: 128,
                totalPrice: 384,
                visibility: .friends,
                paymentMode: .aa,
                queueDuration: .under60,
                diningOccasions: [.friends, .other],
                diningOccasionText: "生日聚餐",
                valueTags: ["合理"],
                environmentTags: ["舒适"],
                serviceTags: ["周到"],
                noiseLevel: .normal,
                diningDuration: .under30,
                portionLevel: .generous,
                transportConvenience: .veryConvenient,
                specialNotes: "靠窗位",
                companionNames: ["小王", "妈妈"],
                recommendationSourceType: .blogger,
                recommendationSourceText: "某美食博主",
                sharedMealID: "shared-p2g",
                note: "原始完整备注"
            )
        )

        let editedAt = Date(timeIntervalSince1970: 1_800_000_000)
        try store.update(
            visit,
            visitedAt: editedAt,
            rating: nil,
            note: "只改这条备注",
            myActualSpend: 150
        )

        #expect(visit.visitedAt == editedAt)
        #expect(visit.rating == nil)
        #expect(visit.note == "只改这条备注")
        #expect(visit.myActualSpend == 150)
        #expect(visit.valueRating == 5)
        #expect(visit.environmentRating == 4)
        #expect(visit.serviceRating == 3.5)
        #expect(visit.totalPrice == 384)
        #expect(visit.visibility == .friends)
        #expect(visit.paymentMode == .aa)
        #expect(visit.queueDuration == .under60)
        #expect(visit.diningOccasions == [.friends, .other])
        #expect(visit.diningOccasionText == "生日聚餐")
        #expect(visit.valueTags == ["合理"])
        #expect(visit.environmentTags == ["舒适"])
        #expect(visit.serviceTags == ["周到"])
        #expect(visit.noiseLevel == .normal)
        #expect(visit.diningDuration == .under30)
        #expect(visit.portionLevel == .generous)
        #expect(visit.transportConvenience == .veryConvenient)
        #expect(visit.specialNotes == "靠窗位")
        #expect(visit.companionNames == ["小王", "妈妈"])
        #expect(visit.companionIDs.count == 2)
        #expect(visit.recommendationSourceType == .blogger)
        #expect(visit.recommendationSourceText == "某美食博主")
        #expect(visit.sharedMealID == "shared-p2g")
        #expect(visit.partySize == 3)

        let mutation = try #require(context.fetch(FetchDescriptor<SyncMutation>()).first {
            $0.entityType == .visit
        })
        let payload = try #require(mutation.payload)
        let contract = try JSONDecoder().decode(VisitSyncContractV1.self, from: payload)
        #expect(contract.rating == nil)
        #expect(contract.valueRating == 5)
        #expect(contract.companions == ["小王", "妈妈"])
        #expect(contract.recommendationSourceText == "某美食博主")
        #expect(contract.specialNotes == "靠窗位")
    }

    @Test("Minimal Visit remains genuinely nullable and does not invent product data")
    func minimalVisitRemainsMinimal() throws {
        let visit = Visit(restaurantId: UUID())
        let record = SyncRecordMapper.visitRecord(visit, restaurantRemoteID: "p2g-minimal")
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any]
        )

        for key in [
            "rating", "valueRating", "environmentRating", "serviceRating", "note",
            "myActualSpend", "totalPrice", "paymentMode", "pricePerPerson", "queueDuration",
            "diningOccasionText", "noiseLevel", "diningDuration", "portionLevel",
            "transportConvenience", "specialNotes", "recommendationSourceId",
            "recommendationSourceType", "recommendationSourceUserId", "recommendationSourceText",
            "sharedMealId",
        ] {
            #expect(object[key] is NSNull)
        }
        for key in [
            "diningOccasions", "valueTags", "environmentTags", "serviceTags",
            "companions", "companionIds",
        ] {
            #expect((object[key] as? [Any])?.isEmpty == true)
        }
    }

    @Test("Large P2 private directories and Restaurant Dish lists remain searchable and stable")
    func moderateDataSetRemainsUsable() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = Restaurant(
            name: "P2-G 负载验收餐厅",
            address: "Development fixture",
            latitude: 30,
            longitude: 120
        )
        context.insert(restaurant)
        let visit = Visit(restaurantId: restaurant.id)
        context.insert(visit)
        for index in 0..<30 {
            context.insert(Dish(
                restaurantId: restaurant.id,
                visitId: visit.id,
                name: String(format: "菜品 %02d", index),
                sortOrder: index
            ))
        }
        for index in 0..<20 {
            context.insert(DiningCompanion(displayName: String(format: "饭搭子 %02d", index)))
            context.insert(RecommendationSource(
                displayName: String(format: "推荐来源 %02d", index),
                sourceType: .other
            ))
        }
        for index in 0..<20 {
            context.insert(PhotoAsset(
                restaurantId: restaurant.id,
                visitId: visit.id,
                kind: .visit,
                fileName: "thumbnail-\(index).jpg",
                mimeType: "image/jpeg",
                byteSize: 24_000,
                width: 480,
                height: 360,
                sortOrder: index,
                thumbnailFileRelativePath: "photos/\(index)/thumbnail.jpg"
            ))
        }
        try context.save()

        let dishes = try context.fetch(FetchDescriptor<Dish>())
            .filter { DishIdentity.normalizedName($0.name).contains("菜品 2") }
            .sorted { $0.name < $1.name }
        let companions = try context.fetch(FetchDescriptor<DiningCompanion>())
            .filter { $0.displayName.contains("饭搭子 1") }
            .sorted { $0.displayName < $1.displayName }
        let sources = try context.fetch(FetchDescriptor<RecommendationSource>())
            .filter { $0.displayName.contains("推荐来源 1") }
            .sorted { $0.displayName < $1.displayName }
        let photos = try context.fetch(FetchDescriptor<PhotoAsset>())
            .sorted { $0.sortOrder < $1.sortOrder }

        #expect(dishes.count == 10)
        #expect(dishes.first?.name == "菜品 20")
        #expect(companions.count == 10)
        #expect(sources.count == 10)
        #expect(photos.count == 20)
        #expect(photos.allSatisfy { $0.thumbnailFileRelativePath != nil })
    }
}
