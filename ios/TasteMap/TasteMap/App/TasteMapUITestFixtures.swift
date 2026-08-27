#if DEBUG
import Foundation
import SwiftData
import UIKit

@MainActor
enum TasteMapUITestFixtures {
    static let detailRestaurantID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    static let detailLaunchArgument = "-p1b-restaurant-detail-fixture"
    static let persistentLaunchArgument = "-p1d-persistent-offline-fixture"
    static let resetPersistentLaunchArgument = "-p1d-reset-persistent-offline-fixture"
    static let persistentConfigurationName = "TasteMapP1DUITests"
    static let persistentEnvironmentKey = "TASTEMAP_P1D_UI_TEST"
    static let resetEnvironmentKey = "TASTEMAP_P1D_RESET"
    static let photoEnvironmentKey = "TASTEMAP_P2B_UI_TEST"
    static let photoFailureEnvironmentKey = "TASTEMAP_P2B_UPLOAD_FAILURE_UI_TEST"

    static var usesPhotoFixture: Bool {
        ProcessInfo.processInfo.environment[photoEnvironmentKey] == "1"
    }

    static var requestsPhotoFailureFixture: Bool {
        ProcessInfo.processInfo.environment[photoFailureEnvironmentKey] == "1"
    }

    static func samplePhotoData() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 1_200, height: 900),
            format: format
        ).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_200, height: 900))
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 180, y: 150, width: 840, height: 600))
        }
        return image.jpegData(compressionQuality: 0.9) ?? Data()
    }

    static var usesPersistentFixture: Bool {
        ProcessInfo.processInfo.environment[persistentEnvironmentKey] == "1"
            || ProcessInfo.processInfo.arguments.contains(persistentLaunchArgument)
    }

    static var requestsPersistentFixtureReset: Bool {
        ProcessInfo.processInfo.environment[resetEnvironmentKey] == "1"
            || ProcessInfo.processInfo.arguments.contains(resetPersistentLaunchArgument)
    }

    static var persistentStoreURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "TasteMapP1DUITests.store")
    }

    static func insertRestaurantDetailFixture(into container: ModelContainer) throws {
        let restaurant = Restaurant(
            id: detailRestaurantID,
            name: "P1-B 想吃餐厅",
            address: "杭州市上城区湖滨路 18 号",
            latitude: 30.259,
            longitude: 120.168,
            appleMapItemIdentifier: "apple-ui-test-p1b",
            city: "杭州",
            status: .wantToGo,
            syncStatus: .synced
        )
        container.mainContext.insert(restaurant)
        try container.mainContext.save()
    }

    static func preparePersistentOfflineFixture(
        in container: ModelContainer,
        reset: Bool
    ) throws {
        let context = container.mainContext
        if reset {
            for photo in try context.fetch(FetchDescriptor<PhotoAsset>()) {
                context.delete(photo)
            }
            for dish in try context.fetch(FetchDescriptor<Dish>()) {
                context.delete(dish)
            }
            for mutation in try context.fetch(FetchDescriptor<SyncMutation>()) {
                context.delete(mutation)
            }
            for checkpoint in try context.fetch(FetchDescriptor<SyncCheckpoint>()) {
                context.delete(checkpoint)
            }
            for visit in try context.fetch(FetchDescriptor<Visit>()) {
                context.delete(visit)
            }
            for restaurant in try context.fetch(FetchDescriptor<Restaurant>()) {
                context.delete(restaurant)
            }
            try context.save()
        }

        let existing = try context.fetch(FetchDescriptor<Restaurant>())
            .first { $0.id == detailRestaurantID }
        guard existing == nil else { return }
        context.insert(Restaurant(
            id: detailRestaurantID,
            name: "P1-D 离线验收餐厅",
            address: "杭州市上城区湖滨路 18 号",
            latitude: 30.259,
            longitude: 120.168,
            appleMapItemIdentifier: "apple-ui-test-p1d",
            city: "杭州",
            status: .wantToGo,
            syncStatus: .synced
        ))
        try context.save()
    }

    static func insertPhotoFailureFixture(into container: ModelContainer) throws {
        let context = container.mainContext
        let restaurant = try context.fetch(FetchDescriptor<Restaurant>())
            .first { $0.id == detailRestaurantID }
        guard let restaurant else { return }
        restaurant.status = .visited
        let visit = Visit(restaurantId: restaurant.id, syncStatus: .pending)
        let photo = PhotoAsset(
            restaurantId: restaurant.id,
            visitId: visit.id,
            kind: .visit,
            fileName: "upload-failure-ui-test.jpg",
            mimeType: "image/jpeg",
            byteSize: 128_000,
            width: 1_200,
            height: 900,
            uploadState: .failed,
            uploadLastError: "网络暂时不可用",
            syncStatus: .pending
        )
        context.insert(visit)
        context.insert(photo)
        try context.save()
    }
}
#endif
