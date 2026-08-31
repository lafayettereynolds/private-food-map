#if DEBUG
import SwiftData
import SwiftUI

#Preview("P2-D · 所有评分为空") {
    P2DRatingPreviewFactory.editor(overall: nil)
}

#Preview("P2-D · 只填写总体评分") {
    P2DRatingPreviewFactory.editor(overall: 4.5)
}

#Preview("P2-D · 部分详细评分") {
    P2DRatingPreviewFactory.editor(overall: 4.5, value: 5, environment: nil, service: 3.5)
}

#Preview("P2-D · 所有评分完整") {
    P2DRatingPreviewFactory.editor(overall: 4.5, value: 4, environment: 5, service: 4.5)
}

#Preview("P2-D · 0.5 星边界") {
    P2DRatingPreviewFactory.editor(overall: 0.5, value: 0.5, environment: nil, service: nil)
}

#Preview("P2-D · 5 星边界") {
    P2DRatingPreviewFactory.editor(overall: 5, value: 5, environment: 5, service: 5)
}

#Preview("P2-D · 编辑已有评分") {
    P2DRatingPreviewFactory.editor(overall: 4, value: 3.5, environment: 4.5, service: 4, synced: true)
}

#Preview("P2-D · 清空其中一项") {
    P2DRatingPreviewFactory.editor(overall: 4, value: 4.5, environment: nil, service: 4)
}

#Preview("P2-D · Restaurant 多维平均") {
    P2DRatingPreviewFactory.detail(partial: false)
}

#Preview("P2-D · Restaurant 部分维度无数据") {
    P2DRatingPreviewFactory.detail(partial: true)
}

@MainActor
private enum P2DRatingPreviewFactory {
    static func editor(
        overall: Double?,
        value: Double? = nil,
        environment: Double? = nil,
        service: Double? = nil,
        synced: Bool = false
    ) -> some View {
        let container = try! TasteMapPersistence.makeContainer(inMemory: true)
        let restaurant = previewRestaurant()
        let visit = Visit(
            restaurantId: restaurant.id,
            rating: overall,
            valueRating: value,
            environmentRating: environment,
            serviceRating: service,
            note: "详细评分仍然全部可选。",
            serverVersion: synced ? 3 : 0,
            syncStatus: synced ? .synced : .pending
        )
        container.mainContext.insert(restaurant)
        container.mainContext.insert(visit)
        return VisitEditorView(restaurant: restaurant, visit: visit)
            .environment(PremiumEntitlementService.preview(status: .premium))
            .modelContainer(container)
    }

    static func detail(partial: Bool) -> some View {
        let container = try! TasteMapPersistence.makeContainer(inMemory: true)
        let restaurant = previewRestaurant()
        container.mainContext.insert(restaurant)
        container.mainContext.insert(Visit(
            restaurantId: restaurant.id,
            visitedAt: Date(timeIntervalSince1970: 1_787_592_000),
            rating: 4.5,
            valueRating: 4,
            environmentRating: partial ? nil : 4.5,
            serviceRating: 5,
            syncStatus: .synced
        ))
        container.mainContext.insert(Visit(
            restaurantId: restaurant.id,
            visitedAt: Date(timeIntervalSince1970: 1_786_000_000),
            rating: 4,
            valueRating: 5,
            environmentRating: partial ? nil : 3.5,
            serviceRating: nil,
            syncStatus: .synced
        ))
        return RestaurantDetailView(restaurant: restaurant)
            .modelContainer(container)
    }

    private static func previewRestaurant() -> Restaurant {
        Restaurant(
            name: "湖边小馆",
            address: "杭州市上城区湖滨路 18 号",
            latitude: 30.259,
            longitude: 120.168,
            appleMapItemIdentifier: "p2d-preview-apple",
            city: "杭州",
            status: .visited,
            syncStatus: .synced
        )
    }
}
#endif
