import Foundation
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

    init(
        context: ModelContext,
        api: any SyncAPI,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.context = context
        self.api = api
        self.queue = SwiftDataSyncQueue(context: context)
        self.now = now
    }

    func synchronize() async throws {
        try prepareLocalState()
        try queue.resetInterruptedUploads()
        try context.save()
        try await pushPendingMutations()
        try await pullChanges()
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
    }

    private func pushPendingMutations() async throws {
        while let mutation = try queue.nextReadyMutation(at: now()) {
            mutation.state = .uploading
            try context.save()
            do {
                let response = try await api.push(SyncPushRequestV1(mutations: [try request(for: mutation)]))
                guard let acknowledgement = response.acknowledgements.first,
                      acknowledgement.mutationId.caseInsensitiveCompare(mutation.mutationID.uuidString) == .orderedSame else {
                    throw SyncEngineError.missingAcknowledgement
                }
                try apply(acknowledgement, for: mutation)
                try context.save()
            } catch {
                mutation.state = .queued
                mutation.retryCount += 1
                mutation.lastError = String(describing: error)
                mutation.nextRetryAt = retryDate(retryCount: mutation.retryCount)
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
        }
        try queue.rebaseActiveMutation(entityType: type, entityID: remoteID, serverVersion: serverVersion, payload: payload)
    }

    private func pullChanges() async throws {
        let checkpoint = try checkpoint()
        repeat {
            let previousCursor = checkpoint.cursor
            let response = try await api.pull(cursor: previousCursor, limit: 200)
            for envelope in response.restaurants { try applyRestaurant(envelope) }
            for envelope in response.visits { try applyVisit(envelope) }
            for tombstone in response.tombstones { try applyTombstone(tombstone) }
            checkpoint.cursor = response.nextCursor
            checkpoint.lastSyncedAt = now()
            try context.save()
            if !response.hasMore { break }
            if response.nextCursor == previousCursor { throw SyncEngineError.cursorDidNotAdvance }
        } while true
    }

    private func applyRestaurant(_ envelope: RestaurantSyncRecordEnvelopeV1) throws {
        let record = envelope.record
        let snapshot = try JSONEncoder().encode(record)
        if let restaurant = try restaurants().first(where: { $0.remoteID == record.id }) {
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
            createdAt: SyncRecordMapper.date(record.createdAt) ?? now(),
            updatedAt: SyncRecordMapper.date(record.updatedAt) ?? now(),
            remoteID: record.id,
            serverVersion: envelope.serverVersion,
            lastSyncedAt: now(),
            syncStatus: .synced
        )
        context.insert(visit)
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
        visit.createdAt = SyncRecordMapper.date(record.createdAt) ?? visit.createdAt
        visit.updatedAt = SyncRecordMapper.date(record.updatedAt) ?? visit.updatedAt
        visit.deletedAt = record.deletedAt.flatMap(SyncRecordMapper.date)
        visit.serverVersion = serverVersion
        visit.lastSyncedAt = now()
        visit.syncStatus = .synced
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

    private func retryDate(retryCount: Int) -> Date {
        let seconds = min(pow(2, Double(max(0, retryCount - 1))) * 5, 60 * 60)
        return now().addingTimeInterval(seconds)
    }

    private func appleIdentifier(_ record: RestaurantJSONContractV1) -> String? {
        record.placeIdentities.first(where: { $0.provider == .appleMaps })?.externalId
    }
}
