import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("F3-A Restaurant Detail Completion", .serialized)
@MainActor
struct RestaurantDetailCompletionTests {
    @Test("完整 Restaurant contract 投影电话、营业时间、参考人均和长期备注")
    func completeMetadataProjection() throws {
        let restaurant = try makeRestaurant()
        let metadata = RestaurantDetailMetadata(restaurant: restaurant)

        #expect(metadata.callablePhone == "+86 571-1234-5678")
        #expect(metadata.websiteURL == nil)
        #expect(metadata.openingHours == "周一至周日 11:00–22:00")
        #expect(metadata.referencePrice == Decimal(168))
        #expect(metadata.longTermNote == "适合周末慢慢吃。")
        #expect(metadata.hasBusinessInformation)
    }

    @Test("空白可选字段保持隐藏而不是显示占位值")
    func emptyMetadataStaysHidden() throws {
        let restaurant = try makeRestaurant(phone: "  ", openingHours: "\n", price: nil, note: " ")
        let metadata = RestaurantDetailMetadata(restaurant: restaurant)

        #expect(metadata.callablePhone == nil)
        #expect(metadata.websiteURL == nil)
        #expect(metadata.openingHours == nil)
        #expect(metadata.referencePrice == nil)
        #expect(metadata.longTermNote == nil)
        #expect(!metadata.hasBusinessInformation)
    }

    @Test("官网只接受真实的 HTTP 或 HTTPS Provider URL")
    func providerWebsiteRequiresSafeWebURL() throws {
        let https = try makeRestaurant(websiteURL: "https://restaurant.example/menu")
        let http = try makeRestaurant(websiteURL: "http://restaurant.example")
        let invalid = try makeRestaurant(websiteURL: "javascript:alert(1)")

        #expect(RestaurantDetailMetadata(restaurant: https).websiteURL?.host == "restaurant.example")
        #expect(RestaurantDetailMetadata(restaurant: http).websiteURL?.scheme == "http")
        #expect(RestaurantDetailMetadata(restaurant: invalid).websiteURL == nil)
    }

    @Test("电话只生成安全 tel URL")
    func safeTelephoneURL() {
        #expect(RestaurantPhoneDialing.url(for: "+86 (571) 1234-5678")?.absoluteString == "tel:+8657112345678")
        #expect(RestaurantPhoneDialing.url(for: "0571;1234") == nil)
        #expect(RestaurantPhoneDialing.url(for: "tel:05711234") == nil)
        #expect(RestaurantPhoneDialing.url(for: "12") == nil)
        #expect(RestaurantPhoneDialing.url(for: nil) == nil)
    }

    @Test("非 HTTPS 商家图不会进入展示来源")
    func merchantImageRequiresHTTPS() throws {
        let unsafe = try makeRestaurant(merchantImageURL: "http://example.test/photo.jpg")
        let safe = try makeRestaurant(merchantImageURL: "https://example.test/photo.jpg")

        #expect(RestaurantDetailMetadata(restaurant: unsafe).merchantImageURL == nil)
        #expect(RestaurantDetailMetadata(restaurant: safe).merchantImageURL?.host == "example.test")
    }

    @Test("平均排队包含正式无需排队样本并排除 nil")
    func queueAverageIncludesNoWaitButNotNil() {
        let id = UUID()
        let visits = [
            makeVisit(restaurantID: id, queue: .noWait),
            makeVisit(restaurantID: id, queue: .under30),
            makeVisit(restaurantID: id, queue: nil),
        ]
        let summary = RestaurantDetailPresentation(restaurantID: id, visits: visits).queueSummary

        #expect(summary == RestaurantQueueSummary(averageMinutes: 12, sampleCount: 2))
    }

    @Test("没有排队样本时不展示虚假平均值")
    func queueAverageWithoutSamplesIsNil() {
        let id = UUID()
        let summary = RestaurantDetailPresentation(
            restaurantID: id,
            visits: [makeVisit(restaurantID: id, queue: nil)]
        ).queueSummary
        #expect(summary == nil)
    }

    @Test("场景和标签按真实频次降序且同频稳定排序")
    func experienceTagsAggregateDeterministically() {
        let id = UUID()
        let visits = [
            makeVisit(restaurantID: id, occasions: [.friends], valueTags: ["划算"], environmentTags: ["舒适", "安静"], serviceTags: ["周到"]),
            makeVisit(restaurantID: id, occasions: [.family], valueTags: ["合理"], environmentTags: ["舒适"], serviceTags: ["周到"]),
            makeVisit(restaurantID: id, occasions: [.friends], valueTags: ["划算"], environmentTags: ["安静"], serviceTags: ["高效"]),
        ]
        let groups = RestaurantDetailPresentation(restaurantID: id, visits: visits).tagGroups

        #expect(groups.first { $0.title == "用餐场景" }?.tags.first == .init(label: "朋友聚餐", count: 2))
        #expect(groups.first { $0.title == "性价比" }?.tags.first == .init(label: "划算", count: 2))
        #expect(groups.first { $0.title == "环境" }?.tags.map(\.count) == [2, 2])
        #expect(groups.first { $0.title == "服务" }?.tags.first == .init(label: "周到", count: 2))
    }

    @Test("同一次 Visit 的重复标签最多计数一次")
    func duplicateTagWithinVisitCountsOnce() {
        let id = UUID()
        let visit = makeVisit(restaurantID: id, valueTags: ["划算", "划算", " 划算 "])
        let group = RestaurantDetailPresentation(restaurantID: id, visits: [visit]).tagGroups
            .first { $0.title == "性价比" }
        #expect(group?.tags == [.init(label: "划算", count: 1)])
    }

    @Test("自定义用餐场景使用用户真实文字")
    func customDiningOccasionUsesUserText() {
        let id = UUID()
        let visit = makeVisit(restaurantID: id, occasions: [.other], occasionText: "老同学重聚")
        let group = RestaurantDetailPresentation(restaurantID: id, visits: [visit]).tagGroups.first
        #expect(group?.tags == [.init(label: "老同学重聚", count: 1)])
    }

    @Test("tombstone Visit 不参与排队与标签聚合")
    func tombstonesAreExcludedFromInsights() {
        let id = UUID()
        let active = makeVisit(restaurantID: id, queue: .noWait, valueTags: ["合理"])
        let deleted = makeVisit(restaurantID: id, queue: .over120, valueTags: ["偏贵"], deletedAt: .now)
        let presentation = RestaurantDetailPresentation(restaurantID: id, visits: [active, deleted])

        #expect(presentation.queueSummary == .init(averageMinutes: 0, sampleCount: 1))
        #expect(presentation.tagGroups.first { $0.title == "性价比" }?.tags == [.init(label: "合理", count: 1)])
    }

    @Test("参考人均与我的实际消费保持两套含义")
    func referencePriceDoesNotReplaceActualSpend() throws {
        let restaurant = try makeRestaurant(price: 168)
        let visit = Visit(restaurantId: restaurant.id, myActualSpend: 88, syncStatus: .synced)

        #expect(RestaurantDetailMetadata(restaurant: restaurant).referencePrice == Decimal(168))
        #expect(RestaurantDetailPresentation(restaurantID: restaurant.id, visits: [visit]).totalSpend == Decimal(88))
    }

    @Test("Discovery 评分只按同用户同 Global Restaurant Identity 投影")
    func ratingReferencesUseExactGlobalIdentity() throws {
        let restaurant = try makeRestaurant()
        let metadata = RestaurantDetailMetadata(restaurant: restaurant)
        let placement = try makePlacement(userID: "tm_owner", globalKey: "apple_maps:apple-f3")

        let values = RestaurantRatingReferenceResolver.resolve(
            metadata: metadata,
            currentUserID: "tm_owner",
            placements: [placement]
        )
        #expect(values.map(\.title) == ["全部用户评分", "好友评分", "同味评分"])
        #expect(values.map(\.sampleCount) == [12, 4, 6])
        #expect(values.map(\.value) == [4.4, 4.8, 4.6])
    }

    @Test("不同 Global Identity 或不同当前用户的评分缓存不会泄漏")
    func ratingReferencesRejectWrongIdentityAndUser() throws {
        let metadata = RestaurantDetailMetadata(restaurant: try makeRestaurant())
        let wrongIdentity = try makePlacement(userID: "tm_owner", globalKey: "apple_maps:other")
        let wrongUser = try makePlacement(userID: "tm_other", globalKey: "apple_maps:apple-f3")

        #expect(RestaurantRatingReferenceResolver.resolve(metadata: metadata, currentUserID: "tm_owner", placements: [wrongIdentity, wrongUser]).isEmpty)
        #expect(RestaurantRatingReferenceResolver.resolve(metadata: metadata, currentUserID: nil, placements: [wrongUser]).isEmpty)
    }

    @Test("无有效样本的公开评分不会显示为零")
    func emptyRatingSamplesStayHidden() throws {
        let metadata = RestaurantDetailMetadata(restaurant: try makeRestaurant())
        let placement = try makePlacement(
            userID: "tm_owner",
            globalKey: "apple_maps:apple-f3",
            ratings: .init(
                mine: .init(value: nil, sampleCount: 0),
                community: .init(value: nil, sampleCount: 0),
                friends: .init(value: 4.9, sampleCount: 0),
                similarTaste: .init(value: nil, sampleCount: 0)
            )
        )
        #expect(RestaurantRatingReferenceResolver.resolve(metadata: metadata, currentUserID: "tm_owner", placements: [placement]).isEmpty)
    }

    @Test("餐厅主图只使用真实 Visit 照片，不使用自定义头像")
    func ownedPhotoHasHighestImagePriority() throws {
        let restaurant = try makeRestaurant(markerPhotoID: "marker-photo", merchantImageURL: "https://example.test/merchant.jpg")
        let marker = makePhoto(restaurantID: restaurant.id, kind: .restaurantMarker, remoteID: "marker-photo", days: 1)
        let recentVisit = makePhoto(restaurantID: restaurant.id, kind: .visit, remoteID: "visit-photo", days: 2)
        let metadata = RestaurantDetailMetadata(restaurant: restaurant)

        let ordered = RestaurantDetailImageResolver.orderedPhotos([recentVisit, marker], metadata: metadata)
        #expect(ordered.map(\.id) == [recentVisit.id])
        #expect(RestaurantDetailImageResolver.preferredSource(photos: ordered, metadata: metadata) == .ownedPhoto(recentVisit.id))
    }

    @Test("无用户实拍时主图使用素材 fallback，不使用商家图")
    func imageFallbackOrder() throws {
        let merchantMetadata = RestaurantDetailMetadata(restaurant: try makeRestaurant(merchantImageURL: "https://example.test/merchant.jpg"))
        let brandMetadata = RestaurantDetailMetadata(restaurant: try makeRestaurant(merchantImageURL: nil, markerEmoji: "🍜"))

        #expect(RestaurantDetailImageResolver.preferredSource(photos: [], metadata: merchantMetadata) == .brand(merchantMetadata.markerEmoji))
        #expect(RestaurantDetailImageResolver.preferredSource(photos: [], metadata: brandMetadata) == .brand("🍜"))
    }

    @Test("正式编辑 mapper 保留身份和位置并把 metadata 写入离线 mutation")
    func metadataEditPreservesIdentityAndEnqueues() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = try makeRestaurant(serverVersion: 7)
        context.insert(restaurant)
        try context.save()

        try LocalTasteMapStore(context: context).updateDetails(
            restaurant,
            name: "  编辑后餐厅  ",
            city: " 杭州 ",
            phone: "+86 571 8765 4321",
            openingHours: " 10:00–23:00 ",
            referencePrice: 199,
            longTermNote: "  下次订窗边  "
        )

        let mutation = try #require(context.fetch(FetchDescriptor<SyncMutation>()).first)
        let payload = try JSONDecoder().decode(
            RestaurantJSONContractV1.self,
            from: #require(mutation.payload)
        )
        #expect(payload.name == "编辑后餐厅")
        #expect(payload.city == "杭州")
        #expect(payload.phone == "+86 571 8765 4321")
        #expect(payload.openingHours == "10:00–23:00")
        #expect(payload.pricePerPerson == 199)
        #expect(payload.longTermNote == "下次订窗边")
        #expect(payload.placeIdentities.first?.externalId == "apple-f3")
        #expect(payload.address == "湖滨路 18 号")
        #expect(payload.latitude == 30.25)
        #expect(payload.longitude == 120.16)
        #expect(restaurant.syncStatus == .pending)
    }

    @Test("清空可选 metadata 会写入 nil 或空合同值")
    func metadataCanBeCleared() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = try makeRestaurant()
        context.insert(restaurant)

        try LocalTasteMapStore(context: context).updateDetails(
            restaurant, name: restaurant.name, city: restaurant.city,
            phone: "", openingHours: " ", referencePrice: nil, longTermNote: "\n"
        )
        let record = try JSONDecoder().decode(RestaurantJSONContractV1.self, from: #require(restaurant.remoteRecordData))
        #expect(record.phone == nil)
        #expect(record.openingHours == nil)
        #expect(record.pricePerPerson == nil)
        #expect(record.longTermNote.isEmpty)
    }

    @Test("非法电话和非正参考人均不会破坏原记录")
    func invalidMetadataIsRejected() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = try makeRestaurant()
        let original = restaurant.remoteRecordData
        context.insert(restaurant)

        #expect(throws: LocalTasteMapStoreError.self) {
            try LocalTasteMapStore(context: context).updateDetails(
                restaurant, name: restaurant.name, city: restaurant.city,
                phone: "tel:1234", openingHours: nil, referencePrice: 100, longTermNote: nil
            )
        }
        #expect(throws: LocalTasteMapStoreError.self) {
            try LocalTasteMapStore(context: context).updateDetails(
                restaurant, name: restaurant.name, city: restaurant.city,
                phone: nil, openingHours: nil, referencePrice: 0, longTermNote: nil
            )
        }
        #expect(restaurant.remoteRecordData == original)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).isEmpty)
    }

    @Test("长文本和多标签不被 presentation 截断或丢弃")
    func longContentRemainsComplete() throws {
        let note = String(repeating: "适合家人聚餐并提前预约。", count: 24)
        let restaurant = try makeRestaurant(note: note)
        let id = restaurant.id
        let tags = (1...10).map { "标签\($0)" }
        let visit = makeVisit(restaurantID: id, environmentTags: tags)

        #expect(RestaurantDetailMetadata(restaurant: restaurant).longTermNote == note)
        #expect(RestaurantDetailPresentation(restaurantID: id, visits: [visit]).tagGroups.first { $0.title == "环境" }?.tags.count == 6)
    }

    @Test("local 与 remote Restaurant Detail 使用同一固定 section contract")
    func globalSectionOrderIsSingleSource() {
        #expect(RestaurantDetailSectionOrderContract.identifiers == [
            "restaurant-photo-gallery",
            "restaurant-detail-header",
            "restaurant-detail-quick-actions",
            "restaurant-business-information",
            "restaurant-detail-location",
            "restaurant-rating-references",
            "restaurant-user-photos",
            "restaurant-detail-statistics",
            "restaurant-visit-history",
        ])
    }

    @Test("所有正式入口只描述来源而不分叉 Restaurant Detail 主体")
    func entrySourceMatrixCoversEveryProductRoute() {
        #expect(Set(RestaurantDetailEntrySource.allCases) == Set([
            .map,
            .list,
            .search,
            .nearby,
            .discovery,
            .community,
            .publicProfile,
            .restaurantList,
            .analysis,
            .roulette,
            .onThisDay,
            .share,
            .unknown,
        ]))
    }

    @Test("remote projection 保留 identity、参考人均和商家图但不伪造私有 metadata")
    func remoteMetadataProjectionIsSafe() {
        let projection = DiscoveryRestaurantProjectionV1(
            globalKey: "apple_maps:remote-f3",
            placeIdentities: [
                .init(provider: .appleMaps, externalId: "remote-f3", isPrimary: true),
            ],
            name: "Remote F3 餐厅", address: "西湖路 9 号", city: "杭州",
            latitude: 30.24, longitude: 120.15, tags: ["日料"],
            pricePerPerson: 238,
            merchantImageUrl: "https://example.test/remote.jpg",
            markerEmoji: "🍣",
            photo: .init(photoId: UUID().uuidString, variant: .thumbnail)
        )
        let metadata = RestaurantDetailMetadata(projection: projection)
        let identity = RestaurantDetailIdentityPresentation(
            projection: projection,
            viewerState: .none
        )

        #expect(metadata.referencePrice == Decimal(238))
        #expect(metadata.merchantImageURL?.host == "example.test")
        #expect(metadata.callablePhone == nil)
        #expect(metadata.openingHours == nil)
        #expect(metadata.longTermNote == nil)
        #expect(metadata.globalIdentityKeys == ["apple_maps:remote-f3"])
        #expect(identity.name == "Remote F3 餐厅")
        #expect(identity.city == "杭州")
        #expect(identity.status == nil)
        #expect(RestaurantDetailIdentityPresentation(
            projection: projection, viewerState: .wantToGo
        ).status == .wantToGo)
    }

    private func makeRestaurant(
        phone: String? = "+86 571-1234-5678",
        openingHours: String? = "周一至周日 11:00–22:00",
        price: Double? = 168,
        note: String = "适合周末慢慢吃。",
        markerPhotoID: String? = nil,
        merchantImageURL: String? = nil,
        websiteURL: String? = nil,
        markerEmoji: String = "🍲",
        serverVersion: Int64 = 0
    ) throws -> Restaurant {
        let restaurant = Restaurant(
            name: "F3-A 餐厅", address: "湖滨路 18 号",
            latitude: 30.25, longitude: 120.16,
            appleMapItemIdentifier: "apple-f3", city: "杭州", status: .visited,
            remoteID: "tm-restaurant-f3", serverVersion: serverVersion,
            syncStatus: serverVersion > 0 ? .synced : .pending
        )
        let timestamp = SyncRecordMapper.dateString(restaurant.updatedAt)
        restaurant.remoteRecordData = try JSONEncoder().encode(RestaurantJSONContractV1(
            id: "tm-restaurant-f3", userId: "tm_owner",
            placeIdentities: [try RestaurantPlaceIdentityContract(
                provider: .appleMaps, externalId: "apple-f3", isPrimary: true,
                createdAt: timestamp, updatedAt: timestamp
            )],
            name: restaurant.name, address: restaurant.address, city: restaurant.city,
            latitude: restaurant.latitude, longitude: restaurant.longitude, status: .visited,
            preferenceLevel: .normal, overallRating: nil, foodRating: nil,
            environmentRating: nil, serviceRating: nil, valueRating: nil,
            tags: ["江浙菜"], longTermNote: note, pricePerPerson: price,
            phone: phone, websiteUrl: websiteURL, openingHours: openingHours, markerType: .emoji,
            markerPhotoId: markerPhotoID, merchantImageUrl: merchantImageURL,
            markerEmoji: markerEmoji, createdAt: timestamp, updatedAt: timestamp,
            deletedAt: nil, isTestData: true
        ))
        return restaurant
    }

    private func makeVisit(
        restaurantID: UUID,
        queue: VisitQueueDuration? = nil,
        occasions: [VisitDiningOccasion] = [],
        occasionText: String? = nil,
        valueTags: [String] = [],
        environmentTags: [String] = [],
        serviceTags: [String] = [],
        deletedAt: Date? = nil
    ) -> Visit {
        Visit(
            restaurantId: restaurantID,
            queueDuration: queue,
            diningOccasions: occasions,
            diningOccasionText: occasionText,
            valueTags: valueTags,
            environmentTags: environmentTags,
            serviceTags: serviceTags,
            deletedAt: deletedAt,
            syncStatus: .synced
        )
    }

    private func makePhoto(
        restaurantID: UUID,
        kind: PhotoAssetKind,
        remoteID: String,
        days: TimeInterval
    ) -> PhotoAsset {
        PhotoAsset(
            restaurantId: restaurantID,
            kind: kind,
            mimeType: "image/jpeg",
            byteSize: 10,
            createdAt: Date(timeIntervalSince1970: days * 86_400),
            remoteID: remoteID,
            syncStatus: .synced
        )
    }

    private func makePlacement(
        userID: String,
        globalKey: String,
        ratings: DiscoveryRatingsV1 = .init(
            mine: .init(value: nil, sampleCount: 0),
            community: .init(value: 4.4, sampleCount: 12),
            friends: .init(value: 4.8, sampleCount: 4),
            similarTaste: .init(value: 4.6, sampleCount: 6)
        )
    ) throws -> CachedDiscoveryPlacement {
        let projection = DiscoveryRestaurantProjectionV1(
            globalKey: globalKey,
            placeIdentities: [.init(provider: .appleMaps, externalId: "apple-f3", isPrimary: true)],
            name: "F3-A 餐厅", address: "湖滨路 18 号", city: "杭州",
            latitude: 30.25, longitude: 120.16, tags: [], pricePerPerson: 168,
            merchantImageUrl: nil, markerEmoji: "🍲", photo: nil
        )
        let card = DiscoveryCardV1(
            id: "for_you:\(globalKey)", mode: .forYou, restaurant: projection,
            viewerState: .visited, ratings: ratings, reasons: [], sourceUser: nil,
            similarity: nil, trend: nil, cacheScope: .public, rank: 1, score: 1
        )
        return try CachedDiscoveryPlacement(
            currentUserID: userID, city: "杭州", trendWindowDays: 7,
            card: card, generatedAt: .now
        )
    }
}
