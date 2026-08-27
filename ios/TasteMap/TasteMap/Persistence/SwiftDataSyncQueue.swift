import Foundation
import SwiftData

extension Notification.Name {
    static let tasteMapSyncMutationQueued = Notification.Name("TasteMapSyncMutationQueued")
}

@MainActor
struct SwiftDataSyncQueue {
    let context: ModelContext

    @discardableResult
    func enqueueUpsert(
        entityType: SyncEntityType,
        entityID: String,
        baseVersion: Int64,
        payload: Data,
        timestamp: Date = .now
    ) throws -> SyncMutation {
        if let pending = try pendingMutation(entityType: entityType, entityID: entityID) {
            pending.operation = .upsert
            pending.payload = payload
            pending.timestamp = timestamp
            pending.nextRetryAt = nil
            pending.lastError = nil
            notifyMutationQueued()
            return pending
        }
        let mutation = SyncMutation(
            entityType: entityType,
            entityID: entityID,
            operation: .upsert,
            timestamp: timestamp,
            payload: payload,
            baseVersion: baseVersion
        )
        context.insert(mutation)
        notifyMutationQueued()
        return mutation
    }

    @discardableResult
    func enqueueDelete(
        entityType: SyncEntityType,
        entityID: String,
        baseVersion: Int64,
        timestamp: Date = .now
    ) throws -> SyncMutation {
        if let pending = try pendingMutation(entityType: entityType, entityID: entityID) {
            pending.operation = .delete
            pending.payload = nil
            pending.timestamp = timestamp
            pending.nextRetryAt = nil
            pending.lastError = nil
            notifyMutationQueued()
            return pending
        }
        let mutation = SyncMutation(
            entityType: entityType,
            entityID: entityID,
            operation: .delete,
            timestamp: timestamp,
            payload: nil,
            baseVersion: baseVersion
        )
        context.insert(mutation)
        notifyMutationQueued()
        return mutation
    }

    func resetInterruptedUploads() throws {
        for mutation in try allMutations() where mutation.state == .uploading {
            mutation.state = .queued
            mutation.nextRetryAt = nil
        }
    }

    func prepareManualRetry() throws {
        for mutation in try allMutations() where mutation.state == .queued || mutation.state == .failed {
            mutation.state = .queued
            mutation.nextRetryAt = nil
            mutation.lastError = nil
        }
    }

    func resetAuthenticationFailures() throws {
        for mutation in try allMutations()
        where mutation.state == .failed && mutation.lastError?.hasPrefix("authentication:") == true {
            mutation.state = .queued
            mutation.nextRetryAt = nil
            mutation.lastError = nil
        }
    }

    func earliestRetryDate() throws -> Date? {
        try allMutations()
            .filter { $0.state == .queued }
            .compactMap(\.nextRetryAt)
            .min()
    }

    func hasConflict(entityType: SyncEntityType, entityID: String) throws -> Bool {
        try allMutations().contains {
            $0.entityType == entityType && $0.entityID == entityID && $0.state == .conflicted
        }
    }

    func nextReadyMutation(at date: Date = .now) throws -> SyncMutation? {
        try allMutations()
            .filter { $0.state == .queued && ($0.nextRetryAt == nil || $0.nextRetryAt! <= date) }
            .sorted {
                if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
                if $0.entityType != $1.entityType { return $0.entityType == .restaurant }
                return $0.mutationID.uuidString < $1.mutationID.uuidString
            }
            .first
    }

    func activeMutation(entityType: SyncEntityType, entityID: String) throws -> SyncMutation? {
        try allMutations().first {
            $0.entityType == entityType && $0.entityID == entityID && $0.state != .conflicted
        }
    }

    func rebaseActiveMutation(
        entityType: SyncEntityType,
        entityID: String,
        serverVersion: Int64,
        payload: Data?
    ) throws {
        guard let mutation = try activeMutation(entityType: entityType, entityID: entityID) else { return }
        mutation.baseVersion = serverVersion
        if mutation.operation == .upsert, let payload { mutation.payload = payload }
    }

    func markConflicted(entityType: SyncEntityType, entityID: String, reason: String) throws {
        for mutation in try allMutations() where mutation.entityType == entityType && mutation.entityID == entityID {
            mutation.state = .conflicted
            mutation.lastError = reason
            mutation.nextRetryAt = nil
        }
    }

    func removeMutations(entityType: SyncEntityType, entityID: String) throws {
        for mutation in try allMutations() where mutation.entityType == entityType && mutation.entityID == entityID {
            context.delete(mutation)
        }
    }

    func allMutations() throws -> [SyncMutation] {
        try context.fetch(FetchDescriptor<SyncMutation>())
    }

    private func pendingMutation(entityType: SyncEntityType, entityID: String) throws -> SyncMutation? {
        try allMutations().first {
            $0.entityType == entityType && $0.entityID == entityID && $0.state == .queued
        }
    }

    private func notifyMutationQueued() {
        NotificationCenter.default.post(name: .tasteMapSyncMutationQueued, object: nil)
    }
}
