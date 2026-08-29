import Foundation
import SwiftData

enum CompanionSourceStoreError: LocalizedError, Equatable {
    case blankName
    case duplicateName
    case missingCompanion
    case missingRecommendationSource
    case targetIsNotFriend

    var errorDescription: String? {
        switch self {
        case .blankName: "名称不能为空。"
        case .duplicateName: "已经有一个完全同名的记录。"
        case .missingCompanion: "没有找到这位饭搭子，请重新选择。"
        case .missingRecommendationSource: "没有找到这个推荐来源，请重新选择。"
        case .targetIsNotFriend: "只能主动关联已经接受的 Taste Map 好友。"
        }
    }
}

@MainActor
struct LocalCompanionSourceStore {
    let context: ModelContext

    @discardableResult
    func findOrCreateCompanion(name: String, ownerUserID: String = "local") throws -> DiningCompanion {
        let name = PrivateDirectoryName.normalized(name)
        guard !name.isEmpty else { throw CompanionSourceStoreError.blankName }
        if let existing = try companions(ownerUserID: ownerUserID).first(where: {
            $0.deletedAt == nil && PrivateDirectoryName.normalized($0.displayName) == name
        }) { return existing }
        let companion = DiningCompanion(ownerUserId: ownerUserID, displayName: name)
        context.insert(companion)
        try enqueue(companion)
        return companion
    }

    @discardableResult
    func findOrCreateRecommendationSource(
        name: String,
        type: RecommendationSourceType = .other,
        ownerUserID: String = "local"
    ) throws -> RecommendationSource {
        let name = PrivateDirectoryName.normalized(name)
        guard !name.isEmpty else { throw CompanionSourceStoreError.blankName }
        if let existing = try recommendationSources(ownerUserID: ownerUserID).first(where: {
            $0.deletedAt == nil && PrivateDirectoryName.normalized($0.displayName) == name
        }) { return existing }
        let source = RecommendationSource(ownerUserId: ownerUserID, displayName: name, sourceType: type)
        context.insert(source)
        try enqueue(source)
        return source
    }

    func rename(_ companion: DiningCompanion, to name: String) throws {
        let name = PrivateDirectoryName.normalized(name)
        guard !name.isEmpty else { throw CompanionSourceStoreError.blankName }
        guard try !companions(ownerUserID: companion.ownerUserId).contains(where: {
            $0.id != companion.id && $0.deletedAt == nil &&
                PrivateDirectoryName.normalized($0.displayName) == name
        }) else { throw CompanionSourceStoreError.duplicateName }
        companion.displayName = name
        companion.updatedAt = .now
        companion.syncStatus = .pending
        try enqueue(companion)
        try context.save()
    }

    func rename(_ source: RecommendationSource, to name: String) throws {
        let name = PrivateDirectoryName.normalized(name)
        guard !name.isEmpty else { throw CompanionSourceStoreError.blankName }
        guard try !recommendationSources(ownerUserID: source.ownerUserId).contains(where: {
            $0.id != source.id && $0.deletedAt == nil &&
                PrivateDirectoryName.normalized($0.displayName) == name
        }) else { throw CompanionSourceStoreError.duplicateName }
        source.displayName = name
        source.updatedAt = .now
        source.syncStatus = .pending
        try enqueue(source)
        try context.save()
    }

    func link(
        _ companion: DiningCompanion,
        toTasteMapUserID userID: String,
        acceptedFriendUserIDs: Set<String>
    ) throws {
        guard acceptedFriendUserIDs.contains(userID) else {
            throw CompanionSourceStoreError.targetIsNotFriend
        }
        companion.linkedTasteMapUserId = userID
        companion.updatedAt = .now
        try enqueue(companion)
        try context.save()
    }

    func unlinkTasteMapUser(from companion: DiningCompanion) throws {
        companion.linkedTasteMapUserId = nil
        companion.updatedAt = .now
        try enqueue(companion)
        try context.save()
    }

    func delete(_ companion: DiningCompanion) throws {
        try softDelete(
            remoteID: companion.remoteID,
            serverVersion: companion.serverVersion,
            entityType: .companion,
            deleteLocal: { context.delete(companion) },
            markDeleted: {
                companion.deletedAt = .now
                companion.updatedAt = companion.deletedAt ?? .now
                companion.syncStatus = .pending
            }
        )
    }

    func delete(_ source: RecommendationSource) throws {
        try softDelete(
            remoteID: source.remoteID,
            serverVersion: source.serverVersion,
            entityType: .recommendationSource,
            deleteLocal: { context.delete(source) },
            markDeleted: {
                source.deletedAt = .now
                source.updatedAt = source.deletedAt ?? .now
                source.syncStatus = .pending
            }
        )
    }

    func materializeSelections(in draft: inout VisitDraft, ownerUserID: String = "local") throws {
        if draft.companionIDs.isEmpty, !draft.companionNames.isEmpty {
            let values = try draft.companionNames.map {
                try findOrCreateCompanion(name: $0, ownerUserID: ownerUserID)
            }
            draft.companionIDs = values.compactMap(\.remoteID)
            draft.companionNames = values.map(\.displayName)
        } else if !draft.companionIDs.isEmpty {
            let all = try companions(ownerUserID: ownerUserID)
            let values = try draft.companionIDs.map { remoteID in
                guard let companion = all.first(where: { $0.remoteID == remoteID && $0.deletedAt == nil }) else {
                    throw CompanionSourceStoreError.missingCompanion
                }
                return companion
            }
            draft.companionNames = values.map(\.displayName)
        }

        if let sourceID = draft.recommendationSourceID {
            guard let source = try recommendationSources(ownerUserID: ownerUserID).first(where: {
                $0.remoteID == sourceID && $0.deletedAt == nil
            }) else { throw CompanionSourceStoreError.missingRecommendationSource }
            draft.recommendationSourceText = source.displayName
            draft.recommendationSourceTypeRawValue = source.sourceType.rawValue
            draft.recommendationSourceUserID = source.linkedTasteMapUserId
        } else if !draft.recommendationSourceText.isEmpty {
            let type = draft.recommendationSourceTypeRawValue
                .flatMap(RecommendationSourceType.init(rawValue:)) ?? .other
            let source = try findOrCreateRecommendationSource(
                name: draft.recommendationSourceText,
                type: type,
                ownerUserID: ownerUserID
            )
            draft.recommendationSourceID = source.remoteID
            draft.recommendationSourceText = source.displayName
            draft.recommendationSourceTypeRawValue = source.sourceType.rawValue
        }
    }

    /// Legacy Web Visits can contain name snapshots and client-side companion IDs
    /// even when their IndexedDB directory was never represented in D1. Build the
    /// missing private directory locally so a fresh native client can reuse and
    /// edit the Visit without discarding those references.
    func materializeLegacyCompanions(
        ids: [String],
        names: [String],
        ownerUserID: String = "local"
    ) throws -> (ids: [String], names: [String]) {
        guard !names.isEmpty else { return ([], []) }
        if ids.isEmpty {
            let values = try names.map { try findOrCreateCompanion(name: $0, ownerUserID: ownerUserID) }
            return (values.compactMap(\.remoteID), names.map(PrivateDirectoryName.normalized))
        }
        guard ids.count == names.count else { return (ids, names) }

        var all = try companions(ownerUserID: ownerUserID)
        var resolvedIDs: [String] = []
        for (remoteID, snapshot) in zip(ids, names) {
            if all.contains(where: { $0.remoteID == remoteID }) {
                resolvedIDs.append(remoteID)
                continue
            }
            let normalizedName = PrivateDirectoryName.normalized(snapshot)
            if let sameName = all.first(where: {
                $0.deletedAt == nil && PrivateDirectoryName.normalized($0.displayName) == normalizedName
            }), let existingID = sameName.remoteID {
                resolvedIDs.append(existingID)
                continue
            }
            let companion = DiningCompanion(
                ownerUserId: ownerUserID,
                displayName: normalizedName,
                remoteID: remoteID
            )
            context.insert(companion)
            try enqueue(companion)
            all.append(companion)
            resolvedIDs.append(remoteID)
        }
        return (resolvedIDs, names.map(PrivateDirectoryName.normalized))
    }

    /// Legacy Web recommendation source fields live directly on Visit. Materialize
    /// non-empty user text as a reusable private source while preserving the Visit
    /// projection as the historical source of truth.
    func materializeLegacyRecommendationSource(
        id: String?,
        typeRawValue: String?,
        text: String?,
        ownerUserID: String = "local"
    ) throws -> String? {
        let normalizedText = PrivateDirectoryName.normalized(text ?? "")
        if let id {
            if try recommendationSources(ownerUserID: ownerUserID).contains(where: { $0.remoteID == id }) {
                return id
            }
            guard !normalizedText.isEmpty else { return id }
            let source = RecommendationSource(
                ownerUserId: ownerUserID,
                displayName: normalizedText,
                sourceType: typeRawValue.flatMap(RecommendationSourceType.init(rawValue:)) ?? .other,
                remoteID: id
            )
            context.insert(source)
            try enqueue(source)
            return id
        }
        guard !normalizedText.isEmpty else { return nil }
        return try findOrCreateRecommendationSource(
            name: normalizedText,
            type: typeRawValue.flatMap(RecommendationSourceType.init(rawValue:)) ?? .other,
            ownerUserID: ownerUserID
        ).remoteID
    }

    func enqueue(_ companion: DiningCompanion) throws {
        let remoteID = companion.remoteID ?? companion.id.uuidString.lowercased()
        companion.remoteID = remoteID
        companion.syncStatus = .pending
        try SwiftDataSyncQueue(context: context).enqueueUpsert(
            entityType: .companion,
            entityID: remoteID,
            baseVersion: companion.serverVersion,
            payload: SyncRecordMapper.companionPayload(companion),
            timestamp: companion.updatedAt
        )
    }

    func enqueue(_ source: RecommendationSource) throws {
        let remoteID = source.remoteID ?? source.id.uuidString.lowercased()
        source.remoteID = remoteID
        source.syncStatus = .pending
        try SwiftDataSyncQueue(context: context).enqueueUpsert(
            entityType: .recommendationSource,
            entityID: remoteID,
            baseVersion: source.serverVersion,
            payload: SyncRecordMapper.recommendationSourcePayload(source),
            timestamp: source.updatedAt
        )
    }

    private func companions(ownerUserID: String? = nil) throws -> [DiningCompanion] {
        let values = try context.fetch(FetchDescriptor<DiningCompanion>())
        guard let ownerUserID else { return values }
        return values.filter { $0.ownerUserId == ownerUserID }
    }

    private func recommendationSources(ownerUserID: String? = nil) throws -> [RecommendationSource] {
        let values = try context.fetch(FetchDescriptor<RecommendationSource>())
        guard let ownerUserID else { return values }
        return values.filter { $0.ownerUserId == ownerUserID }
    }

    private func softDelete(
        remoteID: String?,
        serverVersion: Int64,
        entityType: SyncEntityType,
        deleteLocal: () -> Void,
        markDeleted: () -> Void
    ) throws {
        let queue = SwiftDataSyncQueue(context: context)
        guard let remoteID else {
            deleteLocal()
            try context.save()
            return
        }
        if serverVersion == 0 {
            try queue.removeMutations(entityType: entityType, entityID: remoteID)
            deleteLocal()
        } else {
            markDeleted()
            try queue.enqueueDelete(
                entityType: entityType,
                entityID: remoteID,
                baseVersion: serverVersion
            )
        }
        try context.save()
    }
}
