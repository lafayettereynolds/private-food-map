#if DEBUG
import SwiftData
import SwiftUI

#Preview("P2-C · Visit 无菜品") {
    P2CDishPreviewFactory.visitEditor(dishCount: 0)
}

#Preview("P2-C · Visit 1 道 · 无评分无价格") {
    P2CDishPreviewFactory.visitEditor(dishCount: 1, sparse: true)
}

#Preview("P2-C · Visit 4 道 · 有图无图") {
    P2CDishPreviewFactory.visitEditor(dishCount: 4, includePhotos: true)
}

#Preview("P2-C · Visit 12 道 · 长菜名") {
    P2CDishPreviewFactory.visitEditor(dishCount: 12, longNames: true)
}

#Preview("P2-C · 选择以前吃过的菜") {
    P2CDishPreviewFactory.manager(selectingExisting: true)
}

#Preview("P2-C · 编辑新菜品") {
    P2CDishPreviewFactory.manager(selectingExisting: false)
}

#Preview("P2-C · Restaurant Detail 菜品统计") {
    P2CDishPreviewFactory.restaurantDetail()
}

@MainActor
private enum P2CDishPreviewFactory {
    static func visitEditor(
        dishCount: Int,
        sparse: Bool = false,
        includePhotos: Bool = false,
        longNames: Bool = false
    ) -> some View {
        let fixture = makeFixture(
            dishCount: dishCount,
            sparse: sparse,
            includePhotos: includePhotos,
            longNames: longNames
        )
        return VisitEditorView(restaurant: fixture.restaurant, visit: fixture.visits[0])
            .environment(PremiumEntitlementService.preview(status: .premium))
            .modelContainer(fixture.container)
    }

    static func manager(selectingExisting: Bool) -> some View {
        let fixture = makeFixture(dishCount: 4, includePhotos: true, longNames: true)
        let drafts = selectingExisting
            ? [DishDraft(dish: fixture.dishes[0], photoID: fixture.photos.first?.id)]
            : [DishDraft(
                name: "一道正在新建、名称很长但仍应自然换行的季节限定菜品",
                taste: "比上次清爽，值得再点",
                rating: nil,
                price: nil
            )]
        return DishManagerSheet(
            drafts: .constant(drafts),
            existingDishes: fixture.dishes,
            photos: fixture.photos,
            preparedPhotos: []
        )
        .modelContainer(fixture.container)
    }

    static func restaurantDetail() -> some View {
        let fixture = makeFixture(dishCount: 10, includePhotos: true, longNames: true)
        return RestaurantDetailView(restaurant: fixture.restaurant)
            .modelContainer(fixture.container)
    }

    private static func makeFixture(
        dishCount: Int,
        sparse: Bool = false,
        includePhotos: Bool = false,
        longNames: Bool = false
    ) -> (
        container: ModelContainer,
        restaurant: Restaurant,
        visits: [Visit],
        dishes: [Dish],
        photos: [PhotoAsset]
    ) {
        let container = try! TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = Restaurant(
            name: "湖边小馆",
            address: "杭州市上城区湖滨路 18 号",
            latitude: 30.259,
            longitude: 120.168,
            appleMapItemIdentifier: "p2c-preview-apple",
            city: "杭州",
            status: .visited,
            syncStatus: .synced
        )
        let visits = (0..<3).map { index in
            Visit(
                restaurantId: restaurant.id,
                visitedAt: Calendar.current.date(byAdding: .day, value: -index * 18, to: .now)!,
                rating: index == 2 ? nil : 4.5,
                note: index == 0 ? "和朋友在窗边吃饭。" : nil,
                myActualSpend: index == 0 ? 168 : nil,
                remoteID: "p2c-preview-visit-\(index)",
                syncStatus: .synced
            )
        }
        context.insert(restaurant)
        visits.forEach(context.insert)

        let dishes = (0..<dishCount).map { index in
            Dish(
                restaurantId: restaurant.id,
                visitId: visits[index % visits.count].id,
                name: longNames && index == 0
                    ? "季节限定炭火慢烤澳洲和牛配现磨山葵与三种时令蔬菜"
                    : ["招牌牛肉", "寿司拼盘", "小火锅", "海胆炒饭"][index % 4] + (index >= 4 ? " \(index + 1)" : ""),
                taste: sparse ? "" : (index.isMultiple(of: 2) ? "值得再点，香气很足。" : "这次口味比上次清爽。"),
                rating: sparse ? nil : (index.isMultiple(of: 3) ? nil : Double(7 + index % 4) / 2),
                price: sparse ? nil : Decimal(38 + index * 12),
                sortOrder: index,
                remoteID: "p2c-preview-dish-\(index)",
                serverVersion: 1,
                syncStatus: .synced
            )
        }
        var photos: [PhotoAsset] = []
        for (index, dish) in dishes.enumerated() {
            context.insert(dish)
            let associationVisits = index < 2 ? visits : [visits[0]]
            for visit in associationVisits {
                context.insert(VisitDish(
                    restaurantId: restaurant.id,
                    visitId: visit.id,
                    dishId: dish.id,
                    sortOrder: index,
                    remoteID: "p2c-preview-association-\(index)-\(visit.id.uuidString)",
                    serverVersion: 1,
                    syncStatus: .synced
                ))
            }
            if includePhotos && index.isMultiple(of: 2) {
                let photo = PhotoAsset(
                    restaurantId: restaurant.id,
                    visitId: associationVisits[0].id,
                    dishId: dish.id,
                    kind: .dish,
                    storageProvider: .r2,
                    storageKey: "preview/dish-\(index).jpg",
                    thumbnailStorageKey: "preview/dish-\(index)-thumb.jpg",
                    fileName: "菜品照片 \(index + 1).jpg",
                    mimeType: "image/jpeg",
                    byteSize: 128_000,
                    width: 1_600,
                    height: 1_200,
                    sortOrder: index,
                    uploadState: .uploaded,
                    syncStatus: .synced
                )
                context.insert(photo)
                photos.append(photo)
            }
        }
        try! context.save()
        return (container, restaurant, visits, dishes, photos)
    }
}
#endif
