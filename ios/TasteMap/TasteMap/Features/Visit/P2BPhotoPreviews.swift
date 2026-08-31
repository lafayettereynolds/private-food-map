#if DEBUG
import SwiftData
import SwiftUI

#Preview("P2-B · 空照片 Visit") {
    P2BPhotoPreviewFactory.visitEditor(photoStates: [])
}

#Preview("P2-B · 单张本机照片") {
    P2BPhotoPreviewFactory.visitEditor(photoStates: [.queued])
}

#Preview("P2-B · 多张与失败重试") {
    P2BPhotoPreviewFactory.visitEditor(photoStates: [.uploaded, .uploading, .failed, .queued])
}

#Preview("P2-B · Free 3 张上限") {
    P2BPhotoPreviewFactory.visitEditor(photoStates: [
        .uploaded, .uploading, .queued,
    ], premium: false)
}

#Preview("P2-B · Premium 20 张上限") {
    P2BPhotoPreviewFactory.visitEditor(photoStates: [
        .uploaded, .uploaded, .uploading, .queued, .failed,
        .uploaded, .queued, .uploaded, .uploading, .failed,
        .uploaded, .uploaded, .uploading, .queued, .failed,
        .uploaded, .queued, .uploaded, .uploading, .failed,
    ], premium: true)
}

#Preview("P2-B · 餐厅图库深色", traits: .fixedLayout(width: 393, height: 852)) {
    P2BPhotoPreviewFactory.restaurantDetail(photoStates: [.uploaded, .uploaded, .failed])
        .preferredColorScheme(.dark)
}

#Preview("P2-B · 大字小屏", traits: .fixedLayout(width: 320, height: 568)) {
    P2BPhotoPreviewFactory.visitEditor(photoStates: [.queued, .failed])
        .environment(\.dynamicTypeSize, .accessibility2)
}

@MainActor
private enum P2BPhotoPreviewFactory {
    static func visitEditor(photoStates: [PhotoUploadState], premium: Bool = true) -> some View {
        let fixture = fixture(photoStates: photoStates)
        return VisitEditorView(restaurant: fixture.restaurant, visit: fixture.visit)
            .environment(PremiumEntitlementService.preview(status: premium ? .premium : .free))
            .modelContainer(fixture.container)
    }

    static func restaurantDetail(photoStates: [PhotoUploadState]) -> some View {
        let fixture = fixture(photoStates: photoStates)
        return RestaurantDetailView(restaurant: fixture.restaurant)
            .modelContainer(fixture.container)
    }

    private static func fixture(
        photoStates: [PhotoUploadState]
    ) -> (container: ModelContainer, restaurant: Restaurant, visit: Visit) {
        let container = try! TasteMapPersistence.makeContainer(inMemory: true)
        let restaurant = Restaurant(
            name: "湖边小馆",
            address: "杭州市上城区湖滨路 18 号",
            latitude: 30.259,
            longitude: 120.168,
            appleMapItemIdentifier: "p2b-preview",
            city: "杭州",
            status: .visited,
            syncStatus: .synced
        )
        let visit = Visit(
            restaurantId: restaurant.id,
            rating: 4.5,
            note: "窗边的位置很舒服。",
            diningMode: .dineIn,
            partySize: 2,
            syncStatus: .synced
        )
        container.mainContext.insert(restaurant)
        container.mainContext.insert(visit)
        for (index, state) in photoStates.enumerated() {
            container.mainContext.insert(PhotoAsset(
                restaurantId: restaurant.id,
                visitId: visit.id,
                kind: .visit,
                storageProvider: state == .uploaded ? .r2 : nil,
                storageKey: state == .uploaded ? "preview/display-\(index).jpg" : nil,
                thumbnailStorageKey: state == .uploaded ? "preview/thumb-\(index).jpg" : nil,
                fileName: "到访照片 \(index + 1).jpg",
                mimeType: "image/jpeg",
                byteSize: 128_000,
                width: 1_600,
                height: 1_200,
                sortOrder: index,
                uploadState: state,
                uploadLastError: state == .failed ? "网络暂时不可用" : nil,
                syncStatus: state == .uploaded ? .synced : .pending
            ))
        }
        try! container.mainContext.save()
        return (container, restaurant, visit)
    }
}
#endif
