#if DEBUG
import SwiftData
import SwiftUI

#Preview("Restaurant Detail · 想吃") {
    RestaurantDetailPreviewFactory.make(.wantToGo)
}

#Preview("Restaurant Detail · 去过一次") {
    RestaurantDetailPreviewFactory.make(.oneVisit)
}

#Preview("Restaurant Detail · 多次到访") {
    RestaurantDetailPreviewFactory.make(.manyVisits)
}

#Preview("Restaurant Detail · 数据不足") {
    RestaurantDetailPreviewFactory.make(.sparse)
}

#Preview("Restaurant Detail · 长内容") {
    RestaurantDetailPreviewFactory.make(.longContent)
}

@MainActor
private enum RestaurantDetailPreviewFactory {
    enum State: Equatable {
        case wantToGo
        case oneVisit
        case manyVisits
        case sparse
        case longContent
    }

    static func make(_ state: State) -> some View {
        let container = try! TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = restaurant(for: state)
        context.insert(restaurant)
        visits(for: state, restaurantID: restaurant.id).forEach(context.insert)
        return RestaurantDetailView(restaurant: restaurant)
            .modelContainer(container)
    }

    private static func restaurant(for state: State) -> Restaurant {
        let restaurant: Restaurant
        switch state {
        case .wantToGo:
            restaurant = Restaurant(
                name: "山葵家精致料理",
                address: "杭州市拱墅区湖墅南路 258 号",
                latitude: 30.29,
                longitude: 120.16,
                appleMapItemIdentifier: "preview-apple-want",
                city: "杭州",
                status: .wantToGo,
                syncStatus: .synced
            )
        case .longContent:
            restaurant = Restaurant(
                name: "一家为了验证原生详情页长标题换行能力而使用较长名称的餐厅",
                address: "杭州市西湖区文三路与学院路交叉口向东步行约三百米的沿街商铺二层",
                latitude: 30.28,
                longitude: 120.13,
                appleMapItemIdentifier: "preview-apple-long",
                city: "杭州",
                status: .visited,
                syncStatus: .pending
            )
        default:
            restaurant = Restaurant(
                name: "湖边小馆",
                address: "杭州市上城区湖滨路 18 号",
                latitude: 30.26,
                longitude: 120.17,
                appleMapItemIdentifier: "preview-apple-visited",
                city: "杭州",
                status: .visited,
                syncStatus: .synced
            )
        }
        restaurant.remoteRecordData = metadataRecord(for: restaurant, state: state)
        return restaurant
    }

    private static func metadataRecord(for restaurant: Restaurant, state: State) -> Data? {
        let timestamp = SyncRecordMapper.dateString(restaurant.updatedAt)
        let sparse = state == .sparse
        let long = state == .longContent
        let record = try! RestaurantJSONContractV1(
            id: restaurant.remoteID ?? restaurant.id.uuidString.lowercased(),
            userId: "tm_preview_detail",
            placeIdentities: [try! RestaurantPlaceIdentityContract(
                provider: .appleMaps,
                externalId: restaurant.appleMapItemIdentifier ?? "preview-manual",
                isPrimary: true,
                createdAt: timestamp,
                updatedAt: timestamp
            )],
            name: restaurant.name,
            address: restaurant.address,
            city: restaurant.city,
            latitude: restaurant.latitude,
            longitude: restaurant.longitude,
            status: restaurant.status == .wantToGo ? .wantToGo : .visited,
            preferenceLevel: .normal,
            overallRating: nil,
            foodRating: nil,
            environmentRating: nil,
            serviceRating: nil,
            valueRating: nil,
            tags: sparse ? [] : ["江浙菜", "家常菜"],
            longTermNote: sparse ? "" : (long
                ? "适合带家人慢慢吃。靠窗位置在傍晚光线很好，但周末通常比较忙，最好提前订位。这段长备注用于检查多行内容、动态字体和信息卡片的完整排版。"
                : "适合周末在湖边慢慢吃。"),
            pricePerPerson: sparse ? nil : 168,
            phone: sparse ? nil : "+86 571-1234-5678",
            openingHours: sparse ? nil : "周一至周日 11:00–22:00",
            markerType: .emoji,
            markerPhotoId: nil,
            merchantImageUrl: nil,
            markerEmoji: state == .wantToGo ? "🍣" : "🍲",
            createdAt: timestamp,
            updatedAt: timestamp,
            deletedAt: nil,
            isTestData: true
        )
        return try? JSONEncoder().encode(record)
    }

    private static func visits(for state: State, restaurantID: UUID) -> [Visit] {
        let calendar = Calendar(identifier: .gregorian)
        let base = Date(timeIntervalSince1970: 1_787_592_000)
        func date(daysAgo: Int) -> Date {
            calendar.date(byAdding: .day, value: -daysAgo, to: base)!
        }

        switch state {
        case .wantToGo:
            return []
        case .oneVisit:
            return [Visit(
                restaurantId: restaurantID,
                visitedAt: date(daysAgo: 3),
                rating: 4.5,
                note: "窗边的位置很舒服。",
                myActualSpend: 168,
                queueDuration: .under30,
                diningOccasions: [.date],
                valueTags: ["合理"],
                environmentTags: ["舒适", "景观好"],
                serviceTags: ["周到"],
                syncStatus: .synced
            )]
        case .manyVisits:
            return (0..<6).map { index in
                Visit(
                    restaurantId: restaurantID,
                    visitedAt: date(daysAgo: index * 16),
                    rating: index.isMultiple(of: 3) ? nil : Double(7 + index % 4) / 2,
                    note: index.isMultiple(of: 2) ? "这次点了和平时不同的菜，整体依然稳定。" : nil,
                    myActualSpend: index.isMultiple(of: 2) ? Decimal(90 + index * 18) : nil,
                    queueDuration: index.isMultiple(of: 3) ? .noWait : .under30,
                    diningOccasions: index.isMultiple(of: 2) ? [.friends] : [.family],
                    valueTags: index.isMultiple(of: 2) ? ["划算"] : ["合理"],
                    environmentTags: ["舒适"],
                    serviceTags: index.isMultiple(of: 2) ? ["热情"] : ["高效"],
                    syncStatus: .synced
                )
            }
        case .sparse:
            return [Visit(
                restaurantId: restaurantID,
                visitedAt: date(daysAgo: 12),
                rating: nil,
                note: nil,
                myActualSpend: nil,
                syncStatus: .synced
            )]
        case .longContent:
            return [Visit(
                restaurantId: restaurantID,
                visitedAt: date(daysAgo: 1),
                rating: 4,
                note: "这是一段较长的到访备注，用来验证历史记录在真实内容比较多时依然保持清楚、可扫描，并且不会挤压右侧的操作入口。",
                myActualSpend: 236.5,
                queueDuration: .under60,
                diningOccasions: [.celebration, .other],
                diningOccasionText: "老朋友重聚",
                valueTags: ["合理", "份量合适"],
                environmentTags: ["有氛围", "热闹", "景观好"],
                serviceTags: ["专业", "周到"],
                syncStatus: .pending
            )]
        }
    }
}
#endif
