import Foundation
import OSLog
import SwiftData

enum SyncEngineError: Error, Equatable {
    case missingMutationPayload
    case missingRestaurantMapping
    case missingAcknowledgement
    case cursorDidNotAdvance
}

@MainActor
final class SyncEngine {
    private let context: ModelContext
    private let api: any SyncAPI
    private let queue: SwiftDataSyncQueue
    private let now: @MainActor () -> Date
    private let retryBaseDelay: TimeInterval

    init(
        context: ModelContext,
        api: any SyncAPI,
        now: @escaping @MainActor () -> Date = { .now },
        retryBaseDelay: TimeInterval = 5
    ) {
        self.context = context
        self.api = api
        self.queue = SwiftDataSyncQueue(context: context)
        self.now = now
        self.retryBaseDelay = retryBaseDelay
    }

    func synchronize() async throws {
        engineDebug("Sync pass started")
        try prepareLocalState()
        try queue.resetInterruptedUploads()
        try context.save()
        try await pushPendingMutations()
        try await pullChanges()
        engineDebug("Sync pass completed")
    }

    private func prepareLocalState() throws {
        let localRestaurants = try restaurants()
        for restaurant in localRestaurants {
            if restaurant.remoteID == nil { restaurant.remoteID = restaurant.id.uuidString }
            guard restaurant.serverVersion == 0, restaurant.deletedAt == nil,
                  let remoteID = restaurant.remoteID,
                  try queue.activeMutation(entityType: .restaurant, entityID: remoteID) == nil else { continue }
            try queue.enqueueUpsert(
                entityType: .restaurant,
                entityID: remoteID,
                baseVersion: 0,
                payload: SyncRecordMapper.restaurantPayload(restaurant),
                timestamp: restaurant.updatedAt
            )
        }
        for visit in try visits() {
            if visit.remoteID == nil { visit.remoteID = visit.id.uuidString }
            guard visit.serverVersion == 0, visit.deletedAt == nil,
                  let remoteID = visit.remoteID,
                  try queue.activeMutation(entityType: .visit, entityID: remoteID) == nil,
                  let restaurant = localRestaurants.first(where: { $0.id == visit.restaurantId }),
                  let restaurantRemoteID = restaurant.remoteID else { continue }
            try queue.enqueueUpsert(
                entityType: .visit,
                entityID: remoteID,
                baseVersion: 0,
                payload: SyncRecordMapper.visitPayload(visit, restaurantRemoteID: restaurantRemoteID),
                timestamp: visit.updatedAt
            )
        }
        let localVisits = try visits()
        for dish in try dishes() {
            if dish.remoteID == nil { dish.remoteID = dish.id.uuidString.lowercased() }
            guard dish.serverVersion == 0, dish.deletedAt == nil,
                  let remoteID = dish.remoteID,
                  try queue.activeMutation(entityType: .dish, entityID: remoteID) == nil,
                  let restaurant = localRestaurants.first(where: { $0.id == dish.restaurantId }),
                  let visit = localVisits.first(where: { $0.id == dish.visitId }),
                  let restaurantRemoteID = restaurant.remoteID,
                  let visitRemoteID = visit.remoteID else { continue }
            try queue.enqueueUpsert(
                entityType: .dish,
                entityID: remoteID,
                baseVersion: 0,
                payload: SyncRecordMapper.dishPayload(
                    dish,
                    restaurantRemoteID: restaurantRemoteID,
                    visitRemoteID: visitRemoteID
                ),
                timestamp: dish.updatedAt
            )
        }
        for photo in try photos() {
            if photo.remoteID == nil { photo.remoteID = photo.id.uuidString.lowercased() }
            guard photo.serverVersion == 0, photo.deletedAt == nil,
                  photo.uploadState == .uploaded,
                  let remoteID = photo.remoteID,
                  try queue.activeMutation(entityType: .photo, entityID: remoteID) == nil else { continue }
            let parents = try parentRemoteIDs(for: photo)
            try queue.enqueueUpsert(
                entityType: .photo,
                entityID: remoteID,
                baseVersion: 0,
                payload: SyncRecordMapper.photoPayload(
                    photo,
                    restaurantRemoteID: parents.restaurant,
                    visitRemoteID: parents.visit,
                    dishRemoteID: parents.dish
                ),
                timestamp: photo.updatedAt
            )
        }
    }

    private func pushPendingMutations() async throws {
        while let mutation = try queue.nextReadyMutation(at: now()) {
            mutation.state = .uploading
            try context.save()
            engineDebug("Push started: \(mutation.entityType.rawValue) mutation=\(mutation.mutationID.uuidString.prefix(8))")
            do {
                let response = try await api.push(SyncPushRequestV1(mutations: [try request(for: mutation)]))
                guard let acknowledgement = response.acknowledgements.first,
                      acknowledgement.mutationId.caseInsensitiveCompare(mutation.mutationID.uuidString) == .orderedSame else {
                    throw SyncEngineError.missingAcknowledgement
                }
                try apply(acknowledgement, for: mutation)
                try context.save()
                engineDebug("Push completed: \(mutation.entityType.rawValue)")
            } catch {
                let disposition = SyncErrorClassifier.disposition(for: error)
                mutation.lastError = SyncErrorClassifier.storedReason(for: error, disposition: disposition)
                switch disposition {
                case .retryable:
                    mutation.state = .queued
                    mutation.retryCount += 1
                    mutation.nextRetryAt = retryDate(retryCount: mutation.retryCount)
                    engineDebug("Push queued for retry: \(mutation.entityType.rawValue) attempt=\(mutation.retryCount)")
                case .authentication, .permanent:
                    mutation.state = .failed
                    mutation.retryCount += 1
                    mutation.nextRetryAt = nil
                    markEntityFailed(type: mutation.entityType, remoteID: mutation.entityID)
                    engineDebug("Push stopped: \(disposition.rawValue) \(mutation.entityType.rawValue)")
                case .cancelled:
                    mutation.state = .queued
                    mutation.nextRetryAt = nil
                    engineDebug("Push cancelled and returned to queue")
                }
                try context.save()
                throw error
            }
        }
    }

    private func request(for mutation: SyncMutation) throws -> SyncMutationRequestV1 {
        let payload: SyncMutationPayload?
        switch (mutation.operation, mutation.entityType) {
        case (.delete, _):
            payload = nil
        case (.upsert, .restaurant):
            guard let data = mutation.payload else { throw SyncEngineError.missingMutationPayload }
            payload = .restaurant(try JSONDecoder().decode(RestaurantJSONContractV1.self, from: data))
        case (.upsert, .visit):
            guard let data = mutation.payload else { throw SyncEngineError.missingMutationPayload }
            payload = .visit(try JSONDecoder().decode(VisitSyncContractV1.self, from: data))
        case (.upsert, .dish):
            guard let data = mutation.payload else { throw SyncEngineError.missingMutationPayload }
            payload = .dish(try JSONDecoder().decode(DishSyncContractV1.self, from: data))
        case (.upsert, .photo):
            guard let data = mutation.payload else { throw SyncEngineError.missingMutationPayload }
            payload = .photo(try JSONDecoder().decode(PhotoSyncContractV1.self, from: data))
        }
        return SyncMutationRequestV1(
            mutationId: mutation.mutationID.uuidString.lowercased(),
            entityType: mutation.entityType,
            entityId: mutation.entityID,
            operation: mutation.operation,
            baseVersion: mutation.baseVersion,
            clientTimestamp: SyncRecordMapper.dateString(mutation.timestamp),
            payload: payload
        )
    }

    private func apply(_ acknowledgement: SyncMutationAcknowledgementV1, for mutation: SyncMutation) throws {
        if acknowledgement.status == .conflict {
            mutation.state = .conflicted
            mutation.lastError = acknowledgement.conflictReason ?? "server_conflict"
            markEntityFailed(type: mutation.entityType, remoteID: mutation.entityID)
            engineDebug("Conflict retained locally: \(mutation.entityType.rawValue)")
            return
        }
        context.delete(mutation)
        try rebaseLaterMutation(
            type: mutation.entityType,
            remoteID: mutation.entityID,
            serverVersion: acknowledgement.serverVersion
        )
        markEntitySynced(
            type: mutation.entityType,
            remoteID: mutation.entityID,
            serverVersion: acknowledgement.serverVersion
        )
    }

    private func rebaseLaterMutation(type: SyncEntityType, remoteID: String, serverVersion: Int64) throws {
        let payload: Data?
        switch type {
        case .restaurant:
            let restaurant = try restaurants().first { $0.remoteID == remoteID }
            payload = try restaurant.map(SyncRecordMapper.restaurantPayload)
        case .visit:
            guard let visit = try visits().first(where: { $0.remoteID == remoteID }) else {
                payload = nil
                break
            }
            guard let restaurant = try restaurants().first(where: { $0.id == visit.restaurantId }),
                  let restaurantRemoteID = restaurant.remoteID else {
                throw SyncEngineError.missingRestaurantMapping
            }
            payload = try SyncRecordMapper.visitPayload(visit, restaurantRemoteID: restaurantRemoteID)
        case .dish:
            guard let dish = try dishes().first(where: { $0.remoteID == remoteID }),
                  let restaurant = try restaurants().first(where: { $0.id == dish.restaurantId }),
                  let visit = try visits().first(where: { $0.id == dish.visitId }),
                  let restaurantRemoteID = restaurant.remoteID,
                  let visitRemoteID = visit.remoteID else {
                payload = nil
                break
            }
            payload = try SyncRecordMapper.dishPayload(
                dish,
                restaurantRemoteID: restaurantRemoteID,
                visitRemoteID: visitRemoteID
            )
        case .photo:
            guard let photo = try photos().first(where: { $0.remoteID == remoteID }) else {
                payload = nil
                break
            }
            let parents = try parentRemoteIDs(for: photo)
            payload = try SyncRecordMapper.photoPayload(
                photo,
                restaurantRemoteID: parents.restaurant,
                visitRemoteID: parents.visit,
                dishRemoteID: parents.dish
            )
        }
        try queue.rebaseActiveMutation(entityType: type, entityID: remoteID, serverVersion: serverVersion, payload: payload)
    }

    private func pullChanges() async throws {
        let checkpoint = try checkpoint()
        repeat {
            let previousCursor = checkpoint.cursor
            engineDebug("Pull started cursor=\(previousCursor)")
            let response = try await api.pull(cursor: previousCursor, limit: 200)
            for envelope in response.restaurants { try applyRestaurant(envelope) }
            for envelope in response.visits { try applyVisit(envelope) }
            for envelope in response.dishes { try applyDish(envelope) }
            for envelope in response.photos { try applyPhoto(envelope) }
            for tombstone in response.tombstones { try applyTombstone(tombstone) }
            checkpoint.cursor = response.nextCursor
            checkpoint.lastSyncedAt = now()
            try context.save()
            engineDebug("Pull completed nextCursor=\(response.nextCursor) hasMore=\(response.hasMore)")
            if !response.hasMore { break }
            if response.nextCursor == previousCursor { throw SyncEngineError.cursorDidNotAdvance }
        } while true
    }

    private func applyRestaurant(_ envelope: RestaurantSyncRecordEnvelopeV1) throws {
        let record = envelope.record
        let snapshot = try JSONEncoder().encode(record)
        if let restaurant = try restaurants().first(where: { $0.remoteID == record.id }) {
            if try queue.hasConflict(entityType: .restaurant, entityID: record.id) {
                restaurant.remoteRecordData = snapshot
                engineDebug("Preserved conflicted local Restaurant while recording server snapshot")
                return
            }
            if try queue.activeMutation(entityType: .restaurant, entityID: record.id) != nil {
                if envelope.serverVersion > restaurant.serverVersion {
                    try queue.markConflicted(
                        entityType: .restaurant,
                        entityID: record.id,
                        reason: "server_changed_while_local_mutation_pending"
                    )
                    update(restaurant, from: record, serverVersion: envelope.serverVersion, snapshot: snapshot)
                    restaurant.syncStatus = .failed
                } else if envelope.serverVersion == restaurant.serverVersion {
                    restaurant.remoteRecordData = snapshot
                    try queue.rebaseActiveMutation(
                        entityType: .restaurant,
                        entityID: record.id,
                        serverVersion: envelope.serverVersion,
                        payload: try SyncRecordMapper.restaurantPayload(restaurant)
                    )
                }
                return
            }
            guard envelope.serverVersion >= restaurant.serverVersion else { return }
            update(restaurant, from: record, serverVersion: envelope.serverVersion, snapshot: snapshot)
            return
        }
        let restaurant = Restaurant(
            id: UUID(uuidString: record.id) ?? UUID(),
            name: record.name,
            address: record.address,
            latitude: record.latitude,
            longitude: record.longitude,
            appleMapItemIdentifier: appleIdentifier(record),
            city: record.city,
            status: restaurantStatus(record),
            createdAt: SyncRecordMapper.date(record.createdAt) ?? now(),
            updatedAt: SyncRecordMapper.date(record.updatedAt) ?? now(),
            remoteID: record.id,
            deletedAt: record.deletedAt.flatMap(SyncRecordMapper.date),
            serverVersion: envelope.serverVersion,
            lastSyncedAt: now(),
            syncStatus: .synced,
            remoteRecordData: snapshot
        )
        context.insert(restaurant)
    }

    private func applyVisit(_ envelope: VisitSyncRecordEnvelopeV1) throws {
        let record = envelope.record
        guard let restaurant = try restaurants().first(where: { $0.remoteID == record.restaurantId }) else {
            throw SyncEngineError.missingRestaurantMapping
        }
        if let visit = try visits().first(where: { $0.remoteID == record.id }) {
            if try queue.hasConflict(entityType: .visit, entityID: record.id) {
                engineDebug("Preserved conflicted local Visit during pull")
                return
            }
            if try queue.activeMutation(entityType: .visit, entityID: record.id) != nil {
                if envelope.serverVersion > visit.serverVersion {
                    try queue.markConflicted(
                        entityType: .visit,
                        entityID: record.id,
                        reason: "server_changed_while_local_mutation_pending"
                    )
                    update(visit, from: record, restaurantID: restaurant.id, serverVersion: envelope.serverVersion)
                    visit.syncStatus = .failed
                }
                return
            }
            guard envelope.serverVersion >= visit.serverVersion else { return }
            update(visit, from: record, restaurantID: restaurant.id, serverVersion: envelope.serverVersion)
            return
        }
        let visit = Visit(
            id: UUID(uuidString: record.id) ?? UUID(),
            restaurantId: restaurant.id,
            visitedAt: SyncRecordMapper.date(record.visitedAt) ?? now(),
            rating: record.rating,
            note: record.note,
            myActualSpend: record.myActualSpend.map { Decimal($0) },
            diningMode: record.diningMode,
            partySize: record.partySize,
            createdAt: SyncRecordMapper.date(record.createdAt) ?? now(),
            updatedAt: SyncRecordMapper.date(record.updatedAt) ?? now(),
            remoteID: record.id,
            serverVersion: envelope.serverVersion,
            lastSyncedAt: now(),
            syncStatus: .synced
        )
        context.insert(visit)
    }

    private func applyDish(_ envelope: DishSyncRecordEnvelopeV1) throws {
        let record = envelope.record
        guard let restaurant = try restaurants().first(where: { $0.remoteID == record.restaurantId }),
              let visit = try visits().first(where: { $0.remoteID == record.visitId }) else {
            throw SyncEngineError.missingRestaurantMapping
        }
        let snapshot = try JSONEncoder().encode(record)
        if let dish = try dishes().first(where: { $0.remoteID == record.id }) {
            if try queue.hasConflict(entityType: .dish, entityID: record.id) {
                dish.remoteRecordData = snapshot
                return
            }
            if try queue.activeMutation(entityType: .dish, entityID: record.id) != nil {
                if envelope.serverVersion > dish.serverVersion {
                    try queue.markConflicted(
                        entityType: .dish,
                        entityID: record.id,
                        reason: "server_changed_while_local_mutation_pending"
                    )
                    update(dish, from: record, restaurantID: restaurant.id, visitID: visit.id, serverVersion: envelope.serverVersion, snapshot: snapshot)
                    dish.syncStatus = .failed
                }
                return
            }
            guard envelope.serverVersion >= dish.serverVersion else { return }
            update(dish, from: record, restaurantID: restaurant.id, visitID: visit.id, serverVersion: envelope.serverVersion, snapshot: snapshot)
            return
        }
        context.insert(Dish(
            id: UUID(uuidString: record.id) ?? UUID(),
            restaurantId: restaurant.id,
            visitId: visit.id,
            name: record.name,
            taste: record.taste,
            rating: record.rating,
            price: record.price.map { Decimal($0) },
            photoRemoteID: record.photoId,
            sortOrder: record.sortOrder,
            createdAt: SyncRecordMapper.date(record.createdAt) ?? now(),
            updatedAt: SyncRecordMapper.date(record.updatedAt) ?? now(),
            remoteID: record.id,
            deletedAt: record.deletedAt.flatMap(SyncRecordMapper.date),
            serverVersion: envelope.serverVersion,
            lastSyncedAt: now(),
            syncStatus: .synced,
            remoteRecordData: snapshot
        ))
    }

    private func applyPhoto(_ envelope: PhotoSyncRecordEnvelopeV1) throws {
        let record = envelope.record
        let restaurantID = try record.restaurantId.map { remoteID in
            guard let restaurant = try restaurants().first(where: { $0.remoteID == remoteID }) else {
                throw SyncEngineError.missingRestaurantMapping
            }
            return restaurant.id
        }
        let visitID = try record.visitId.map { remoteID in
            guard let visit = try visits().first(where: { $0.remoteID == remoteID }) else {
                throw SyncEngineError.missingRestaurantMapping
            }
            return visit.id
        }
        let dishID = try record.dishId.map { remoteID in
            guard let dish = try dishes().first(where: { $0.remoteID == remoteID }) else {
                throw SyncEngineError.missingRestaurantMapping
            }
            return dish.id
        }
        let snapshot = try JSONEncoder().encode(record)
        if let photo = try photos().first(where: { $0.remoteID == record.id }) {
            if try queue.hasConflict(entityType: .photo, entityID: record.id) {
                photo.remoteRecordData = snapshot
                return
            }
            if try queue.activeMutation(entityType: .photo, entityID: record.id) != nil {
                if envelope.serverVersion > photo.serverVersion {
                    try queue.markConflicted(
                        entityType: .photo,
                        entityID: record.id,
                        reason: "server_changed_while_local_mutation_pending"
                    )
                    update(photo, from: record, restaurantID: restaurantID, visitID: visitID, dishID: dishID, serverVersion: envelope.serverVersion, snapshot: snapshot)
                    photo.syncStatus = .failed
                }
                return
            }
            guard envelope.serverVersion >= photo.serverVersion else { return }
            update(photo, from: record, restaurantID: restaurantID, visitID: visitID, dishID: dishID, serverVersion: envelope.serverVersion, snapshot: snapshot)
            return
        }
        context.insert(PhotoAsset(
            id: UUID(uuidString: record.id) ?? UUID(),
            restaurantId: restaurantID,
            visitId: visitID,
            dishId: dishID,
            kind: record.kind,
            storageProvider: record.storageProvider,
            storageKey: record.storageKey,
            providerAccountId: record.providerAccountId,
            thumbnailStorageKey: record.thumbnailStorageKey,
            fileName: record.fileName,
            mimeType: record.mimeType,
            byteSize: record.byteSize,
            width: record.width,
            height: record.height,
            sortOrder: record.sortOrder,
            visibility: record.visibility,
            uploadState: .uploaded,
            createdAt: SyncRecordMapper.date(record.createdAt) ?? now(),
            updatedAt: SyncRecordMapper.date(record.updatedAt) ?? now(),
            remoteID: record.id,
            deletedAt: record.deletedAt.flatMap(SyncRecordMapper.date),
            serverVersion: envelope.serverVersion,
            lastSyncedAt: now(),
            syncStatus: .synced,
            remoteRecordData: snapshot
        ))
    }

    private func applyTombstone(_ tombstone: SyncTombstoneV1) throws {
        let deletedAt = SyncRecordMapper.date(tombstone.deletedAt) ?? now()
        try queue.markConflicted(entityType: tombstone.entityType, entityID: tombstone.entityId, reason: "server_tombstone")
        switch tombstone.entityType {
        case .restaurant:
            guard let restaurant = try restaurants().first(where: { $0.remoteID == tombstone.entityId }) else { return }
            restaurant.deletedAt = deletedAt
            restaurant.serverVersion = tombstone.serverVersion
            restaurant.lastSyncedAt = now()
            restaurant.syncStatus = .synced
        case .visit:
            guard let visit = try visits().first(where: { $0.remoteID == tombstone.entityId }) else { return }
            visit.deletedAt = deletedAt
            visit.serverVersion = tombstone.serverVersion
            visit.lastSyncedAt = now()
            visit.syncStatus = .synced
        case .dish:
            guard let dish = try dishes().first(where: { $0.remoteID == tombstone.entityId }) else { return }
            dish.deletedAt = deletedAt
            dish.serverVersion = tombstone.serverVersion
            dish.lastSyncedAt = now()
            dish.syncStatus = .synced
        case .photo:
            guard let photo = try photos().first(where: { $0.remoteID == tombstone.entityId }) else { return }
            photo.deletedAt = deletedAt
            photo.serverVersion = tombstone.serverVersion
            photo.lastSyncedAt = now()
            photo.uploadState = .deleted
            photo.syncStatus = .synced
        }
    }

    private func update(
        _ restaurant: Restaurant,
        from record: RestaurantJSONContractV1,
        serverVersion: Int64,
        snapshot: Data
    ) {
        restaurant.name = record.name
        restaurant.address = record.address
        restaurant.city = record.city
        restaurant.latitude = record.latitude
        restaurant.longitude = record.longitude
        restaurant.appleMapItemIdentifier = appleIdentifier(record)
        restaurant.status = restaurantStatus(record)
        restaurant.createdAt = SyncRecordMapper.date(record.createdAt) ?? restaurant.createdAt
        restaurant.updatedAt = SyncRecordMapper.date(record.updatedAt) ?? restaurant.updatedAt
        restaurant.deletedAt = record.deletedAt.flatMap(SyncRecordMapper.date)
        restaurant.serverVersion = serverVersion
        restaurant.lastSyncedAt = now()
        restaurant.syncStatus = .synced
        restaurant.remoteRecordData = snapshot
    }

    private func update(
        _ visit: Visit,
        from record: VisitSyncContractV1,
        restaurantID: UUID,
        serverVersion: Int64
    ) {
        visit.restaurantId = restaurantID
        visit.visitedAt = SyncRecordMapper.date(record.visitedAt) ?? visit.visitedAt
        visit.rating = Visit.validatedRating(record.rating)
        visit.note = record.note
        visit.myActualSpend = record.myActualSpend.map { Decimal($0) }
        visit.diningMode = record.diningMode
        visit.partySize = record.partySize
        visit.createdAt = SyncRecordMapper.date(record.createdAt) ?? visit.createdAt
        visit.updatedAt = SyncRecordMapper.date(record.updatedAt) ?? visit.updatedAt
        visit.deletedAt = record.deletedAt.flatMap(SyncRecordMapper.date)
        visit.serverVersion = serverVersion
        visit.lastSyncedAt = now()
        visit.syncStatus = .synced
    }

    private func update(
        _ dish: Dish,
        from record: DishSyncContractV1,
        restaurantID: UUID,
        visitID: UUID,
        serverVersion: Int64,
        snapshot: Data
    ) {
        dish.restaurantId = restaurantID
        dish.visitId = visitID
        dish.name = record.name
        dish.taste = record.taste
        dish.rating = Visit.validatedRating(record.rating)
        dish.price = record.price.map { Decimal($0) }
        dish.photoRemoteID = record.photoId
        dish.sortOrder = record.sortOrder
        dish.createdAt = SyncRecordMapper.date(record.createdAt) ?? dish.createdAt
        dish.updatedAt = SyncRecordMapper.date(record.updatedAt) ?? dish.updatedAt
        dish.deletedAt = record.deletedAt.flatMap(SyncRecordMapper.date)
        dish.serverVersion = serverVersion
        dish.lastSyncedAt = now()
        dish.syncStatus = .synced
        dish.remoteRecordData = snapshot
    }

    private func update(
        _ photo: PhotoAsset,
        from record: PhotoSyncContractV1,
        restaurantID: UUID?,
        visitID: UUID?,
        dishID: UUID?,
        serverVersion: Int64,
        snapshot: Data
    ) {
        photo.restaurantId = restaurantID
        photo.visitId = visitID
        photo.dishId = dishID
        photo.kind = record.kind
        photo.storageProvider = record.storageProvider
        photo.storageKey = record.storageKey
        photo.providerAccountId = record.providerAccountId
        photo.thumbnailStorageKey = record.thumbnailStorageKey
        photo.fileName = record.fileName
        photo.mimeType = record.mimeType
        photo.byteSize = record.byteSize
        photo.width = record.width
        photo.height = record.height
        photo.sortOrder = record.sortOrder
        photo.visibility = record.visibility
        photo.uploadState = .uploaded
        photo.createdAt = SyncRecordMapper.date(record.createdAt) ?? photo.createdAt
        photo.updatedAt = SyncRecordMapper.date(record.updatedAt) ?? photo.updatedAt
        photo.deletedAt = record.deletedAt.flatMap(SyncRecordMapper.date)
        photo.serverVersion = serverVersion
        photo.lastSyncedAt = now()
        photo.syncStatus = .synced
        photo.remoteRecordData = snapshot
    }

    private func markEntitySynced(type: SyncEntityType, remoteID: String, serverVersion: Int64) {
        let hasLaterMutation = (try? queue.activeMutation(entityType: type, entityID: remoteID)) != nil
        switch type {
        case .restaurant:
            guard let restaurant = try? restaurants().first(where: { $0.remoteID == remoteID }) else { return }
            restaurant.serverVersion = serverVersion
            restaurant.lastSyncedAt = now()
            restaurant.syncStatus = hasLaterMutation ? .pending : .synced
        case .visit:
            guard let visit = try? visits().first(where: { $0.remoteID == remoteID }) else { return }
            visit.serverVersion = serverVersion
            visit.lastSyncedAt = now()
            visit.syncStatus = hasLaterMutation ? .pending : .synced
        case .dish:
            guard let dish = try? dishes().first(where: { $0.remoteID == remoteID }) else { return }
            dish.serverVersion = serverVersion
            dish.lastSyncedAt = now()
            dish.syncStatus = hasLaterMutation ? .pending : .synced
        case .photo:
            guard let photo = try? photos().first(where: { $0.remoteID == remoteID }) else { return }
            photo.serverVersion = serverVersion
            photo.lastSyncedAt = now()
            photo.syncStatus = hasLaterMutation ? .pending : .synced
        }
    }

    private func markEntityFailed(type: SyncEntityType, remoteID: String) {
        switch type {
        case .restaurant:
            if let restaurant = try? restaurants().first(where: { $0.remoteID == remoteID }) {
                restaurant.syncStatus = .failed
            }
        case .visit:
            if let visit = try? visits().first(where: { $0.remoteID == remoteID }) {
                visit.syncStatus = .failed
            }
        case .dish:
            if let dish = try? dishes().first(where: { $0.remoteID == remoteID }) {
                dish.syncStatus = .failed
            }
        case .photo:
            if let photo = try? photos().first(where: { $0.remoteID == remoteID }) {
                photo.syncStatus = .failed
            }
        }
    }

    private func checkpoint() throws -> SyncCheckpoint {
        if let existing = try context.fetch(FetchDescriptor<SyncCheckpoint>()).first { return existing }
        let checkpoint = SyncCheckpoint()
        context.insert(checkpoint)
        return checkpoint
    }

    private func restaurants() throws -> [Restaurant] {
        try context.fetch(FetchDescriptor<Restaurant>())
    }

    private func visits() throws -> [Visit] {
        try context.fetch(FetchDescriptor<Visit>())
    }

    private func dishes() throws -> [Dish] {
        try context.fetch(FetchDescriptor<Dish>())
    }

    private func photos() throws -> [PhotoAsset] {
        try context.fetch(FetchDescriptor<PhotoAsset>())
    }

    private func parentRemoteIDs(for photo: PhotoAsset) throws -> (restaurant: String?, visit: String?, dish: String?) {
        let restaurant = try photo.restaurantId.flatMap { id in
            try restaurants().first(where: { $0.id == id })?.remoteID
        }
        let visit = try photo.visitId.flatMap { id in
            try visits().first(where: { $0.id == id })?.remoteID
        }
        let dish = try photo.dishId.flatMap { id in
            try dishes().first(where: { $0.id == id })?.remoteID
        }
        if photo.restaurantId != nil && restaurant == nil { throw SyncEngineError.missingRestaurantMapping }
        if photo.visitId != nil && visit == nil { throw SyncEngineError.missingRestaurantMapping }
        if photo.dishId != nil && dish == nil { throw SyncEngineError.missingRestaurantMapping }
        return (restaurant, visit, dish)
    }

    private func retryDate(retryCount: Int) -> Date {
        let seconds = min(
            pow(2, Double(max(0, retryCount - 1))) * retryBaseDelay,
            60 * 60
        )
        return now().addingTimeInterval(seconds)
    }

    private func appleIdentifier(_ record: RestaurantJSONContractV1) -> String? {
        record.placeIdentities.first(where: { $0.provider == .appleMaps })?.externalId
    }

    private func restaurantStatus(_ record: RestaurantJSONContractV1) -> RestaurantStatus {
        switch record.status {
        case .visited: .visited
        case .wantToGo: .wantToGo
        }
    }
}

nonisolated private func engineDebug(_ message: String) {
#if DEBUG
    Logger(subsystem: "com.lafayette.tastemap", category: "SyncEngine")
        .debug("\(message, privacy: .public)")
#endif
}
