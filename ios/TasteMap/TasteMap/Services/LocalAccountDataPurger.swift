import Foundation
import SwiftData

nonisolated struct AccountDeletionLocalPurgeResult: Equatable, Sendable {
    let deletedRecordCount: Int
    let deletedPhotoFileCount: Int
}

nonisolated struct LocalAccountContentClearResult: Equatable, Sendable {
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

    /// Clears the current device's private content without deleting the account,
    /// profile, active profile avatar, entitlement, or sync checkpoint. Remote
    /// records are intentionally untouched and may be restored by a later full
    /// account sync or import.
    func clearCurrentAccountContent(userID: String) async throws -> LocalAccountContentClearResult {
        let profiles = try context.fetch(FetchDescriptor<UserProfile>()).filter {
            $0.tasteMapUserID == userID && $0.deletedAt == nil
        }
        let retainedPhotoIDs = Set(profiles.compactMap(\.avatarPhotoID).map { $0.lowercased() })
        let ownedPhotos = try context.fetch(FetchDescriptor<PhotoAsset>()).filter {
            $0.ownerUserID == userID
        }
        let retainedPhotos = ownedPhotos.filter { photo in
            let localID = photo.id.uuidString.lowercased()
            let remoteID = photo.remoteID?.lowercased()
            return retainedPhotoIDs.contains(localID) || remoteID.map(retainedPhotoIDs.contains) == true
        }
        let retainedPhotoEntityIDs = Set(retainedPhotos.flatMap { photo in
            [photo.id.uuidString.lowercased(), photo.remoteID?.lowercased()].compactMap { $0 }
        })
        let photos = ownedPhotos.filter { photo in
            !retainedPhotoEntityIDs.contains(photo.id.uuidString.lowercased()) &&
                !(photo.remoteID.map { retainedPhotoEntityIDs.contains($0.lowercased()) } ?? false)
        }
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
        deletedRecordCount += try deleteOwned(VisitDish.self, userID: userID) { $0.ownerUserID }
        deletedRecordCount += try deleteOwned(Dish.self, userID: userID) { $0.ownerUserID }
        photos.forEach(context.delete)
        deletedRecordCount += photos.count
        deletedRecordCount += try deleteOwned(Visit.self, userID: userID) { $0.ownerUserID }
        deletedRecordCount += try deleteOwned(Restaurant.self, userID: userID) { $0.ownerUserID }
        deletedRecordCount += try deleteOwned(DiningCompanion.self, userID: userID) { $0.ownerUserId }
        deletedRecordCount += try deleteOwned(RecommendationSource.self, userID: userID) { $0.ownerUserId }
        deletedRecordCount += try deleteOwned(RestaurantListItem.self, userID: userID) { $0.ownerUserID }
        deletedRecordCount += try deleteOwned(RestaurantList.self, userID: userID) { $0.ownerUserID }

        let mutations = try context.fetch(FetchDescriptor<SyncMutation>()).filter { mutation in
            guard mutation.ownerUserID == userID else { return false }
            if mutation.entityType == .profile { return false }
            if mutation.entityType == .photo,
               retainedPhotoEntityIDs.contains(mutation.entityID.lowercased()) { return false }
            return true
        }
        mutations.forEach(context.delete)
        deletedRecordCount += mutations.count

        let socialMutationCount = try context.fetch(FetchDescriptor<SocialMutation>())
            .filter { $0.currentUserID == userID }.count
        deletedRecordCount += socialMutationCount
        try LocalSocialStore(context: context).purgeSocialDerivedCaches(currentUserID: userID)
        try LocalRestaurantListStore(context: context).purgePublicCache(viewerUserID: userID)
        try context.save()
        return LocalAccountContentClearResult(
            deletedRecordCount: deletedRecordCount,
            deletedPhotoFileCount: deletedPhotoFileCount
        )
    }

    func purgeCurrentAccount(userID: String) async throws -> AccountDeletionLocalPurgeResult {
        let photos = try context.fetch(FetchDescriptor<PhotoAsset>()).filter {
            $0.ownerUserID == userID
        }
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
        deletedRecordCount += try deleteOwned(VisitDish.self, userID: userID) { $0.ownerUserID }
        deletedRecordCount += try deleteOwned(Dish.self, userID: userID) { $0.ownerUserID }
        photos.forEach(context.delete)
        deletedRecordCount += photos.count
        deletedRecordCount += try deleteOwned(Visit.self, userID: userID) { $0.ownerUserID }
        deletedRecordCount += try deleteOwned(Restaurant.self, userID: userID) { $0.ownerUserID }
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

        deletedRecordCount += try deleteOwned(SyncMutation.self, userID: userID) { $0.ownerUserID }
        deletedRecordCount += try deleteOwned(SyncCheckpoint.self, userID: userID) { $0.ownerUserID }
        deletedRecordCount += try context.fetch(FetchDescriptor<SocialMutation>())
            .filter { $0.currentUserID == userID }.count
        try LocalSocialStore(context: context).purgeSocialDerivedCaches(currentUserID: userID)
        try LocalRestaurantListStore(context: context).purgePublicCache(viewerUserID: userID)
        try context.save()
        RecommendationPreferenceLedger.purge(owner: userID)
        return AccountDeletionLocalPurgeResult(
            deletedRecordCount: deletedRecordCount,
            deletedPhotoFileCount: deletedPhotoFileCount
        )
    }

    private func deleteOwned<Model: PersistentModel>(
        _ type: Model.Type,
        userID: String,
        owner: (Model) -> String
    ) throws -> Int {
        let values = try context.fetch(FetchDescriptor<Model>())
        let owned = values.filter { owner($0) == userID }
        owned.forEach(context.delete)
        return owned.count
    }
}
