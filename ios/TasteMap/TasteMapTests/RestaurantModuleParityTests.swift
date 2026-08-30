import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("Task 03 Restaurant module parity", .serialized)
@MainActor
struct RestaurantModuleParityTests {
    @Test("完整编辑更新地址状态和 marker，同时保持全局身份与坐标")
    func fullEditPreservesGlobalIdentity() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = try makeRestaurant(serverVersion: 4)
        let marker = PhotoAsset(
            ownerUserID: "tm_owner",
            restaurantId: restaurant.id,
            kind: .restaurantMarker,
            mimeType: "image/jpeg",
            byteSize: 42,
            remoteID: "photo-marker-task03",
            serverVersion: 2,
            syncStatus: .synced
        )
        context.insert(restaurant)
        context.insert(marker)
        try context.save()

        try LocalTasteMapStore(context: context).updateDetails(
            restaurant,
            update: RestaurantDetailsUpdate(
                name: "  新餐厅名  ",
                address: " 新地址 88 号 ",
                city: " 上海 ",
                status: .wantToGo,
                phone: "+86 21 1234 5678",
                openingHours: "10:00–22:00",
                referencePrice: 208,
                longTermNote: "下次约朋友",
                markerType: .image,
                markerPhotoID: "photo-marker-task03",
                markerEmoji: "🥘"
            )
        )

        let record = try SyncRecordMapper.restaurantRecord(restaurant)
        #expect(restaurant.name == "新餐厅名")
        #expect(restaurant.address == "新地址 88 号")
        #expect(restaurant.city == "上海")
        #expect(restaurant.status == .wantToGo)
        #expect(restaurant.latitude == 30.25)
        #expect(restaurant.longitude == 120.16)
        #expect(restaurant.appleMapItemIdentifier == "apple-task03")
        #expect(record.id == "restaurant-task03")
        #expect(record.placeIdentities.first?.externalId == "apple-task03")
        #expect(record.markerType == .image)
        #expect(record.markerPhotoId == "photo-marker-task03")
        #expect(record.markerEmoji == "🥘")
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).first?.operation == .upsert)
    }

    @Test("不能把其他餐厅或非 marker 照片写成正式 marker")
    func markerPhotoMustBelongToRestaurant() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = try makeRestaurant()
        let visitPhoto = PhotoAsset(
            ownerUserID: "tm_owner",
            restaurantId: restaurant.id,
            kind: .visit,
            mimeType: "image/jpeg",
            byteSize: 10,
            remoteID: "visit-photo"
        )
        context.insert(restaurant)
        context.insert(visitPhoto)

        #expect(throws: LocalTasteMapStoreError.self) {
            try LocalTasteMapStore(context: context).updateDetails(
                restaurant,
                update: update(for: restaurant, markerPhotoID: "visit-photo")
            )
        }
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).isEmpty)
    }

    @Test("分享 hook 默认没有假 URL 且不泄露个人记录")
    func shareHookIsPrivacySafe() throws {
        let restaurant = try makeRestaurant()
        let payload = RestaurantSharingService.payload(
            restaurant: restaurant,
            metadata: RestaurantDetailMetadata(restaurant: restaurant)
        )

        #expect(payload.publicURL == nil)
        #expect(payload.message.contains("Task 03 餐厅"))
        #expect(payload.message.contains("湖滨路 18 号"))
        #expect(!payload.message.contains("我的"))
        #expect(!payload.message.contains("到访"))
        #expect(!payload.message.contains("下次约朋友"))
    }

    @Test("已同步 Restaurant 删除保留完整 tombstone 图并按子实体优先排队")
    func syncedDeleteCreatesOrderedTombstones() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = try makeRestaurant(serverVersion: 8)
        let visit = Visit(
            ownerUserID: "tm_owner",
            restaurantId: restaurant.id,
            remoteID: "visit-task03",
            serverVersion: 7,
            syncStatus: .synced
        )
        let dish = Dish(
            ownerUserID: "tm_owner",
            restaurantId: restaurant.id,
            visitId: visit.id,
            name: "代表菜",
            remoteID: "dish-task03",
            serverVersion: 6,
            syncStatus: .synced
        )
        let association = VisitDish(
            ownerUserID: "tm_owner",
            restaurantId: restaurant.id,
            visitId: visit.id,
            dishId: dish.id,
            remoteID: "visit-dish-task03",
            serverVersion: 5,
            syncStatus: .synced
        )
        let photo = PhotoAsset(
            ownerUserID: "tm_owner",
            restaurantId: restaurant.id,
            visitId: visit.id,
            dishId: dish.id,
            kind: .dish,
            storageProvider: .r2,
            storageKey: "users/tm_owner/task03.jpg",
            mimeType: "image/jpeg",
            byteSize: 100,
            uploadState: .uploaded,
            remoteID: "photo-task03",
            serverVersion: 4,
            syncStatus: .synced
        )
        context.insert(restaurant)
        context.insert(visit)
        context.insert(dish)
        context.insert(association)
        context.insert(photo)
        try context.save()

        try LocalTasteMapStore(context: context).delete(restaurant, actorUserID: "tm_owner")

        #expect(restaurant.deletedAt != nil)
        #expect(visit.deletedAt != nil)
        #expect(dish.deletedAt != nil)
        #expect(association.deletedAt != nil)
        #expect(photo.deletedAt != nil)
        #expect(photo.uploadState == .deleted)
        #expect(visit.restaurantId == restaurant.id)
        #expect(dish.restaurantId == restaurant.id)

        let queue = SwiftDataSyncQueue(context: context, ownerUserID: "tm_owner")
        var orderedTypes: [SyncEntityType] = []
        while let mutation = try queue.nextReadyMutation() {
            #expect(mutation.operation == .delete)
            orderedTypes.append(mutation.entityType)
            context.delete(mutation)
            try context.save()
        }
        #expect(orderedTypes == [.photo, .visitDish, .dish, .visit, .restaurant])
    }

    @Test("未同步 Restaurant 删除可离线完成且不会留下 upsert 复活记录")
    func offlineDeleteRemovesUpsertsAndRetainsPhotoCleanupTombstone() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = try makeRestaurant(serverVersion: 0)
        let visit = Visit(ownerUserID: "tm_owner", restaurantId: restaurant.id)
        let photo = PhotoAsset(
            ownerUserID: "tm_owner",
            restaurantId: restaurant.id,
            visitId: visit.id,
            kind: .visit,
            mimeType: "image/jpeg",
            byteSize: 12,
            localFileRelativePath: "photos/task03.jpg"
        )
        context.insert(restaurant)
        context.insert(visit)
        context.insert(photo)
        try SwiftDataSyncQueue(context: context, ownerUserID: "tm_owner").enqueueUpsert(
            entityType: .restaurant,
            entityID: restaurant.remoteID!,
            baseVersion: 0,
            payload: SyncRecordMapper.restaurantPayload(restaurant)
        )
        try context.save()

        try LocalTasteMapStore(context: context).delete(restaurant, actorUserID: "tm_owner")

        #expect(restaurant.deletedAt != nil)
        #expect(photo.deletedAt != nil)
        #expect(try context.fetch(FetchDescriptor<Visit>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).isEmpty)
    }

    @Test("客户端 actor 不能删除其他 owner 的 Restaurant")
    func ownershipMismatchIsRejected() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = try makeRestaurant(serverVersion: 8)
        context.insert(restaurant)
        try context.save()

        #expect(throws: LocalTasteMapStoreError.self) {
            try LocalTasteMapStore(context: context).delete(restaurant, actorUserID: "tm_other")
        }
        #expect(restaurant.deletedAt == nil)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).isEmpty)
    }

    private func update(for restaurant: Restaurant, markerPhotoID: String?) -> RestaurantDetailsUpdate {
        RestaurantDetailsUpdate(
            name: restaurant.name,
            address: restaurant.address,
            city: restaurant.city,
            status: restaurant.status,
            phone: nil,
            openingHours: nil,
            referencePrice: nil,
            longTermNote: nil,
            markerType: .image,
            markerPhotoID: markerPhotoID,
            markerEmoji: "🍽️"
        )
    }

    private func makeRestaurant(serverVersion: Int64 = 0) throws -> Restaurant {
        let restaurant = Restaurant(
            ownerUserID: "tm_owner",
            name: "Task 03 餐厅",
            address: "湖滨路 18 号",
            latitude: 30.25,
            longitude: 120.16,
            appleMapItemIdentifier: "apple-task03",
            city: "杭州",
            status: .visited,
            remoteID: "restaurant-task03",
            serverVersion: serverVersion,
            syncStatus: serverVersion == 0 ? .pending : .synced
        )
        let timestamp = SyncRecordMapper.dateString(restaurant.updatedAt)
        restaurant.remoteRecordData = try JSONEncoder().encode(RestaurantJSONContractV1(
            id: "restaurant-task03",
            userId: "tm_owner",
            placeIdentities: [try RestaurantPlaceIdentityContract(
                provider: .appleMaps,
                externalId: "apple-task03",
                isPrimary: true,
                createdAt: timestamp,
                updatedAt: timestamp
            )],
            name: restaurant.name,
            address: restaurant.address,
            city: restaurant.city,
            latitude: restaurant.latitude,
            longitude: restaurant.longitude,
            status: .visited,
            preferenceLevel: .normal,
            overallRating: nil,
            foodRating: nil,
            environmentRating: nil,
            serviceRating: nil,
            valueRating: nil,
            tags: ["江浙菜"],
            longTermNote: "私人长期备注：下次约朋友",
            pricePerPerson: 168,
            phone: "+86 571 1234 5678",
            openingHours: "11:00–22:00",
            markerType: .emoji,
            markerPhotoId: nil,
            merchantImageUrl: nil,
            markerEmoji: "🍲",
            createdAt: timestamp,
            updatedAt: timestamp,
            deletedAt: nil,
            isTestData: true
        ))
        return restaurant
    }
}
