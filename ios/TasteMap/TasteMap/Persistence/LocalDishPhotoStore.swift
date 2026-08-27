import Foundation
import SwiftData

enum LocalDishPhotoStoreError: Error, Equatable {
    case restaurantNotFound
    case visitNotFound
    case dishNotFound
    case relationshipMismatch
    case missingRemoteMapping
}

@MainActor
struct LocalDishPhotoStore {
    let context: ModelContext
    let photoFiles: any LocalPhotoFileStoring

    init(context: ModelContext, photoFiles: any LocalPhotoFileStoring) {
        self.context = context
        self.photoFiles = photoFiles
    }

    @discardableResult
    func createDish(
        restaurantId: UUID,
        visitId: UUID,
        name: String,
        taste: String = "",
        rating: Double? = nil,
        price: Decimal? = nil,
        sortOrder: Int = 0
    ) throws -> Dish {
        let parents = try activeParents(restaurantId: restaurantId, visitId: visitId)
        let dish = Dish(
            restaurantId: restaurantId,
            visitId: visitId,
            name: name,
            taste: taste,
            rating: rating,
            price: price,
            sortOrder: sortOrder
        )
        context.insert(dish)
        try enqueue(dish, restaurant: parents.restaurant, visit: parents.visit)
        try context.save()
        return dish
    }

    func update(
        _ dish: Dish,
        name: String,
        taste: String,
        rating: Double?,
        price: Decimal?,
        sortOrder: Int
    ) throws {
        let parents = try activeParents(restaurantId: dish.restaurantId, visitId: dish.visitId)
        dish.name = name
        dish.taste = taste
        dish.rating = Visit.validatedRating(rating)
        dish.price = price.flatMap { $0 >= 0 ? $0 : nil }
        dish.sortOrder = max(0, sortOrder)
        dish.updatedAt = .now
        try enqueue(dish, restaurant: parents.restaurant, visit: parents.visit)
        try context.save()
    }

    func delete(_ dish: Dish) throws {
        let queue = SwiftDataSyncQueue(context: context)
        let remoteID = dish.remoteID ?? dish.id.uuidString.lowercased()
        if dish.serverVersion == 0 {
            try queue.removeMutations(entityType: .dish, entityID: remoteID)
            context.delete(dish)
        } else {
            dish.deletedAt = .now
            dish.updatedAt = dish.deletedAt ?? .now
            dish.syncStatus = .pending
            try queue.enqueueDelete(
                entityType: .dish,
                entityID: remoteID,
                baseVersion: dish.serverVersion,
                timestamp: dish.updatedAt
            )
        }
        try context.save()
    }

    @discardableResult
    func createLocalPhoto(
        data: Data,
        mimeType: String,
        kind: PhotoAssetKind,
        restaurantId: UUID? = nil,
        visitId: UUID? = nil,
        dishId: UUID? = nil,
        fileName: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        sortOrder: Int = 0,
        visibility: PhotoVisibility = .private
    ) async throws -> PhotoAsset {
        try validatePhotoRelationship(
            kind: kind,
            restaurantId: restaurantId,
            visitId: visitId,
            dishId: dishId
        )
        let photoID = UUID()
        let relativePath = try await photoFiles.save(data, photoID: photoID, mimeType: mimeType)
        let photo = PhotoAsset(
            id: photoID,
            restaurantId: restaurantId,
            visitId: visitId,
            dishId: dishId,
            kind: kind,
            fileName: fileName,
            mimeType: mimeType,
            byteSize: Int64(data.count),
            width: width,
            height: height,
            sortOrder: sortOrder,
            visibility: visibility,
            localFileRelativePath: relativePath,
            uploadState: .localOnly,
            syncStatus: .pending
        )
        do {
            context.insert(photo)
            try context.save()
            return photo
        } catch {
            context.delete(photo)
            try? await photoFiles.delete(relativePath: relativePath)
            throw error
        }
    }

    @discardableResult
    func createLocalPhoto(
        prepared: PreparedLocalPhoto,
        kind: PhotoAssetKind,
        restaurantId: UUID? = nil,
        visitId: UUID? = nil,
        dishId: UUID? = nil,
        sortOrder: Int = 0,
        visibility: PhotoVisibility = .private,
        queueForUpload: Bool = false,
        draftSessionID: UUID? = nil
    ) throws -> PhotoAsset {
        try validatePhotoRelationship(
            kind: kind,
            restaurantId: restaurantId,
            visitId: visitId,
            dishId: dishId
        )
        let photo = PhotoAsset(
            id: prepared.id,
            restaurantId: restaurantId,
            visitId: visitId,
            dishId: dishId,
            kind: kind,
            fileName: prepared.originalFileName,
            mimeType: prepared.displayMimeType,
            byteSize: prepared.displayByteSize,
            width: prepared.width,
            height: prepared.height,
            sortOrder: sortOrder,
            visibility: visibility,
            localFileRelativePath: prepared.originalFileRelativePath,
            displayFileRelativePath: prepared.displayFileRelativePath,
            thumbnailFileRelativePath: prepared.thumbnailFileRelativePath,
            displayContentHash: prepared.displayContentHash,
            thumbnailContentHash: prepared.thumbnailContentHash,
            uploadState: queueForUpload ? .queued : .localOnly,
            uploadMutationID: UUID(),
            draftSessionID: draftSessionID,
            syncStatus: .pending
        )
        context.insert(photo)
        try context.save()
        return photo
    }

    func queueUpload(_ photo: PhotoAsset) throws {
        guard photo.deletedAt == nil else { return }
        photo.uploadState = .queued
        photo.uploadLastError = nil
        photo.uploadRetryAfter = nil
        photo.uploadMutationID = photo.uploadMutationID ?? UUID()
        photo.draftSessionID = nil
        photo.updatedAt = .now
        try context.save()
    }

    func markUploading(_ photo: PhotoAsset) throws {
        guard photo.deletedAt == nil else { return }
        photo.uploadState = .uploading
        photo.uploadLastError = nil
        photo.updatedAt = .now
        try context.save()
    }

    func markUploadFailed(_ photo: PhotoAsset, reason: String, retryAfter: Date? = nil) throws {
        photo.uploadState = .failed
        photo.uploadRetryCount += 1
        photo.uploadLastError = String(reason.prefix(300))
        photo.uploadRetryAfter = retryAfter
        photo.updatedAt = .now
        try context.save()
    }

    func markUploaded(_ photo: PhotoAsset, reference: StoredPhotoReference) throws {
        guard photo.deletedAt == nil else { return }
        photo.storageProvider = reference.storageProvider
        photo.storageKey = reference.storageKey
        photo.providerAccountId = reference.providerAccountId
        photo.thumbnailStorageKey = reference.thumbnailStorageKey
        photo.fileName = reference.metadata.originalFileName ?? photo.fileName
        photo.mimeType = reference.metadata.contentType
        photo.byteSize = reference.metadata.byteSize
        photo.width = reference.metadata.pixelWidth
        photo.height = reference.metadata.pixelHeight
        photo.uploadState = .uploaded
        photo.uploadRetryCount = 0
        photo.uploadLastError = nil
        photo.uploadRetryAfter = nil
        photo.cachedStorageKey = reference.storageKey
        photo.cachedThumbnailStorageKey = reference.thumbnailStorageKey
        photo.updatedAt = .now
        try enqueue(photo)
        try context.save()
    }

    func discardLocalPhoto(_ photo: PhotoAsset) async throws {
        guard photo.serverVersion == 0, photo.storageKey == nil else {
            try delete(photo)
            return
        }
        let paths = localPaths(photo)
        try SwiftDataSyncQueue(context: context).removeMutations(
            entityType: .photo,
            entityID: photo.remoteID ?? photo.id.uuidString.lowercased()
        )
        context.delete(photo)
        try context.save()
        for path in paths { try? await photoFiles.delete(relativePath: path) }
    }

    func delete(_ photo: PhotoAsset) throws {
        let remoteID = photo.remoteID ?? photo.id.uuidString.lowercased()
        let queue = SwiftDataSyncQueue(context: context)
        photo.deletedAt = .now
        photo.updatedAt = photo.deletedAt ?? .now
        photo.uploadState = .deleted
        photo.syncStatus = .pending
        if photo.serverVersion == 0 {
            try queue.removeMutations(entityType: .photo, entityID: remoteID)
        } else {
            try queue.enqueueDelete(
                entityType: .photo,
                entityID: remoteID,
                baseVersion: photo.serverVersion,
                timestamp: photo.updatedAt
            )
        }
        try context.save()
    }

    func setDishRelationship(_ photo: PhotoAsset, dish: Dish?) throws {
        guard let restaurantId = photo.restaurantId, let visitId = photo.visitId else {
            throw LocalDishPhotoStoreError.visitNotFound
        }
        if let dish {
            try validatePhotoRelationship(
                kind: .dish,
                restaurantId: restaurantId,
                visitId: visitId,
                dishId: dish.id
            )
            photo.kind = .dish
            photo.dishId = dish.id
        } else {
            photo.kind = .visit
            photo.dishId = nil
        }
        photo.updatedAt = .now
        if photo.uploadState == .uploaded { try enqueue(photo) }
        try context.save()
    }

    func cleanupLocalFiles(retainingTombstonesFor retention: TimeInterval = 7 * 24 * 60 * 60) async throws {
        let cutoff = Date().addingTimeInterval(-retention)
        let photos = try context.fetch(FetchDescriptor<PhotoAsset>())
        for photo in photos where photo.deletedAt.map({ $0 <= cutoff }) == true {
            for relativePath in localPaths(photo) {
                try await photoFiles.delete(relativePath: relativePath)
            }
            photo.localFileRelativePath = nil
            photo.displayFileRelativePath = nil
            photo.thumbnailFileRelativePath = nil
        }
        try context.save()
    }

    func referencedLocalPaths() throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<PhotoAsset>()).flatMap(localPaths))
    }

    private func enqueue(_ dish: Dish, restaurant: Restaurant, visit: Visit) throws {
        guard let restaurantRemoteID = restaurant.remoteID,
              let visitRemoteID = visit.remoteID else {
            throw LocalDishPhotoStoreError.missingRemoteMapping
        }
        let remoteID = dish.remoteID ?? dish.id.uuidString.lowercased()
        dish.remoteID = remoteID
        dish.syncStatus = .pending
        try SwiftDataSyncQueue(context: context).enqueueUpsert(
            entityType: .dish,
            entityID: remoteID,
            baseVersion: dish.serverVersion,
            payload: SyncRecordMapper.dishPayload(
                dish,
                restaurantRemoteID: restaurantRemoteID,
                visitRemoteID: visitRemoteID
            ),
            timestamp: dish.updatedAt
        )
    }

    private func enqueue(_ photo: PhotoAsset) throws {
        let remoteIDs = try photoParentRemoteIDs(photo)
        let remoteID = photo.remoteID ?? photo.id.uuidString.lowercased()
        photo.remoteID = remoteID
        photo.syncStatus = .pending
        try SwiftDataSyncQueue(context: context).enqueueUpsert(
            entityType: .photo,
            entityID: remoteID,
            baseVersion: photo.serverVersion,
            payload: SyncRecordMapper.photoPayload(
                photo,
                restaurantRemoteID: remoteIDs.restaurant,
                visitRemoteID: remoteIDs.visit,
                dishRemoteID: remoteIDs.dish
            ),
            timestamp: photo.updatedAt
        )
    }

    private func activeParents(restaurantId: UUID, visitId: UUID) throws -> (restaurant: Restaurant, visit: Visit) {
        guard let restaurant = try context.fetch(FetchDescriptor<Restaurant>())
            .first(where: { $0.id == restaurantId && $0.deletedAt == nil }) else {
            throw LocalDishPhotoStoreError.restaurantNotFound
        }
        guard let visit = try context.fetch(FetchDescriptor<Visit>())
            .first(where: { $0.id == visitId && $0.deletedAt == nil }) else {
            throw LocalDishPhotoStoreError.visitNotFound
        }
        guard visit.restaurantId == restaurant.id else { throw LocalDishPhotoStoreError.relationshipMismatch }
        return (restaurant, visit)
    }

    private func validatePhotoRelationship(
        kind: PhotoAssetKind,
        restaurantId: UUID?,
        visitId: UUID?,
        dishId: UUID?
    ) throws {
        switch kind {
        case .restaurantMarker:
            guard let restaurantId else { throw LocalDishPhotoStoreError.restaurantNotFound }
            guard try context.fetch(FetchDescriptor<Restaurant>()).contains(where: {
                $0.id == restaurantId && $0.deletedAt == nil
            }) else { throw LocalDishPhotoStoreError.restaurantNotFound }
        case .visit:
            guard let restaurantId, let visitId else { throw LocalDishPhotoStoreError.visitNotFound }
            _ = try activeParents(restaurantId: restaurantId, visitId: visitId)
        case .dish:
            guard let restaurantId, let visitId, let dishId else { throw LocalDishPhotoStoreError.dishNotFound }
            _ = try activeParents(restaurantId: restaurantId, visitId: visitId)
            guard try context.fetch(FetchDescriptor<Dish>()).contains(where: {
                $0.id == dishId && $0.restaurantId == restaurantId && $0.deletedAt == nil
            }) else { throw LocalDishPhotoStoreError.dishNotFound }
            let isOriginVisit = try context.fetch(FetchDescriptor<Dish>()).contains(where: {
                $0.id == dishId && $0.visitId == visitId
            })
            let isAssociatedVisit = try context.fetch(FetchDescriptor<VisitDish>()).contains(where: {
                $0.dishId == dishId && $0.visitId == visitId && $0.deletedAt == nil
            })
            guard isOriginVisit || isAssociatedVisit else { throw LocalDishPhotoStoreError.relationshipMismatch }
        case .avatar:
            break
        }
    }

    private func photoParentRemoteIDs(_ photo: PhotoAsset) throws -> (restaurant: String?, visit: String?, dish: String?) {
        let restaurant = try photo.restaurantId.flatMap { id in
            try context.fetch(FetchDescriptor<Restaurant>()).first(where: { $0.id == id })?.remoteID
        }
        let visit = try photo.visitId.flatMap { id in
            try context.fetch(FetchDescriptor<Visit>()).first(where: { $0.id == id })?.remoteID
        }
        let dish = try photo.dishId.flatMap { id in
            try context.fetch(FetchDescriptor<Dish>()).first(where: { $0.id == id })?.remoteID
        }
        if photo.restaurantId != nil && restaurant == nil { throw LocalDishPhotoStoreError.missingRemoteMapping }
        if photo.visitId != nil && visit == nil { throw LocalDishPhotoStoreError.missingRemoteMapping }
        if photo.dishId != nil && dish == nil { throw LocalDishPhotoStoreError.missingRemoteMapping }
        return (restaurant, visit, dish)
    }

    private func localPaths(_ photo: PhotoAsset) -> [String] {
        [
            photo.localFileRelativePath,
            photo.displayFileRelativePath,
            photo.thumbnailFileRelativePath,
        ].compactMap { $0 }
    }
}
