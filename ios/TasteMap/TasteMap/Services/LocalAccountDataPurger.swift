import Foundation
import SwiftData

nonisolated struct AccountDeletionLocalPurgeResult: Equatable, Sendable {
    let deletedRecordCount: Int
    let deletedPhotoFileCount: Int
}

@MainActor
struct LocalAccountDataPurger {
    let context: ModelContext
    let photoFileStore: any LocalPhotoFileStoring

    init(context: ModelContext) throws {
        self.context = context
        photoFileStore = try LocalPhotoFileStore()
    }

    init(context: ModelContext, photoFileStore: any LocalPhotoFileStoring) {
        self.context = context
        self.photoFileStore = photoFileStore
    }

    func purgeCurrentAccount(userID: String) async throws -> AccountDeletionLocalPurgeResult {
        let photos = try context.fetch(FetchDescriptor<PhotoAsset>())
        let photoPaths = Set(photos.flatMap {
            [$0.localFileRelativePath, $0.displayFileRelativePath, $0.thumbnailFileRelativePath]
                .compactMap { $0 }
        })
        var deletedPhotoFileCount = 0
        for path in photoPaths {
            if await photoFileStore.fileExists(relativePath: path) {
                try await photoFileStore.delete(relativePath: path)
                deletedPhotoFileCount += 1
            }
        }

        var deletedRecordCount = 0
        deletedRecordCount += try deleteAll(VisitDish.self)
        deletedRecordCount += try deleteAll(Dish.self)
        deletedRecordCount += try deleteAll(PhotoAsset.self)
        deletedRecordCount += try deleteAll(Visit.self)
        deletedRecordCount += try deleteAll(Restaurant.self)
        let companions = try context.fetch(FetchDescriptor<DiningCompanion>(
            predicate: #Predicate { $0.ownerUserId == userID }
        ))
        companions.forEach(context.delete)
        deletedRecordCount += companions.count
        let sources = try context.fetch(FetchDescriptor<RecommendationSource>(
            predicate: #Predicate { $0.ownerUserId == userID }
        ))
        sources.forEach(context.delete)
        deletedRecordCount += sources.count
        let listItems = try context.fetch(FetchDescriptor<RestaurantListItem>(
            predicate: #Predicate { $0.ownerUserID == userID }
        ))
        listItems.forEach(context.delete)
        deletedRecordCount += listItems.count

        let lists = try context.fetch(FetchDescriptor<RestaurantList>(
            predicate: #Predicate { $0.ownerUserID == userID }
        ))
        lists.forEach(context.delete)
        deletedRecordCount += lists.count

        let profiles = try context.fetch(FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.tasteMapUserID == userID }
        ))
        profiles.forEach(context.delete)
        deletedRecordCount += profiles.count

        deletedRecordCount += try deleteAll(SyncMutation.self)
        deletedRecordCount += try deleteAll(SyncCheckpoint.self)
        deletedRecordCount += try deleteAll(SocialMutation.self)
        try LocalSocialStore(context: context).purgeAllSocialDerivedCaches()
        try LocalRestaurantListStore(context: context).purgePublicCache()
        try context.save()
        return AccountDeletionLocalPurgeResult(
            deletedRecordCount: deletedRecordCount,
            deletedPhotoFileCount: deletedPhotoFileCount
        )
    }

    private func deleteAll<Model: PersistentModel>(_ type: Model.Type) throws -> Int {
        let values = try context.fetch(FetchDescriptor<Model>())
        values.forEach(context.delete)
        return values.count
    }
}
