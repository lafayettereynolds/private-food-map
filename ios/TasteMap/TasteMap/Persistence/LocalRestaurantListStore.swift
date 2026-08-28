import CryptoKit
import Foundation
import SwiftData

enum RestaurantListStoreError: Error, Equatable, LocalizedError {
    case invalidTitle
    case descriptionTooLong
    case noteTooLong
    case duplicateRestaurant
    case listNotFound
    case itemNotFound
    case invalidReorder
    case notOwner

    var errorDescription: String? {
        switch self {
        case .invalidTitle: "榜单标题需要 1–60 个字符。"
        case .descriptionTooLong: "榜单描述最多 240 个字符。"
        case .noteTooLong: "入选理由最多 160 个字符。"
        case .duplicateRestaurant: "这家餐厅已经在榜单里。"
        case .listNotFound: "没有找到这份榜单。"
        case .itemNotFound: "没有找到这条榜单记录。"
        case .invalidReorder: "榜单顺序已经变化，请刷新后重试。"
        case .notOwner: "只有榜单创建者可以修改。"
        }
    }
}

@MainActor
struct LocalRestaurantListStore {
    let context: ModelContext
    private var queue: SwiftDataSyncQueue { SwiftDataSyncQueue(context: context) }

    @discardableResult
    func create(
        ownerUserID: String,
        title: String,
        description: String = "",
        visibility: RestaurantListVisibility = .private,
        isRanked: Bool = false
    ) throws -> RestaurantList {
        let fields = try Self.normalized(title: title, description: description)
        let list = RestaurantList(
            ownerUserID: ownerUserID,
            title: fields.title,
            listDescription: fields.description,
            visibility: visibility,
            isRanked: isRanked
        )
        context.insert(list)
        try enqueue(list)
        try context.save()
        return list
    }

    func update(
        _ list: RestaurantList,
        actorUserID: String,
        title: String,
        description: String,
        visibility: RestaurantListVisibility,
        isRanked: Bool,
        coverMode: RestaurantListCoverMode? = nil,
        customCoverPhotoID: String? = nil
    ) throws {
        try assertOwner(list, actorUserID: actorUserID)
        let fields = try Self.normalized(title: title, description: description)
        list.title = fields.title
        list.listDescription = fields.description
        list.visibility = visibility
        list.isRanked = isRanked
        if let coverMode {
            list.coverMode = coverMode
            list.customCoverPhotoID = coverMode == .custom ? customCoverPhotoID : nil
        }
        list.updatedAt = .now
        list.syncStatus = .pending
        try enqueue(list)
        try context.save()
    }

    func delete(_ list: RestaurantList, actorUserID: String) throws {
        try assertOwner(list, actorUserID: actorUserID)
        let now = Date.now
        for item in try items(listID: list.id, includeDeleted: false) {
            item.deletedAt = now
            item.updatedAt = now
            item.syncStatus = .pending
            try queue.enqueueDelete(
                entityType: .restaurantListItem,
                entityID: item.remoteID ?? item.id.uuidString.lowercased(),
                baseVersion: item.serverVersion,
                timestamp: now
            )
        }
        list.deletedAt = now
        list.updatedAt = now
        list.activeItemCount = 0
        list.previewRestaurantIDs = []
        list.previewRestaurants = []
        list.syncStatus = .pending
        try queue.enqueueDelete(
            entityType: .restaurantList,
            entityID: list.remoteID ?? list.id.uuidString.lowercased(),
            baseVersion: list.serverVersion,
            timestamp: now.addingTimeInterval(0.001)
        )
        try context.save()
    }

    @discardableResult
    func add(
        restaurant: Restaurant,
        to list: RestaurantList,
        actorUserID: String,
        note: String = ""
    ) throws -> RestaurantListItem {
        let place = try place(for: restaurant)
        return try add(
            place: place,
            localRestaurantID: restaurant.id,
            to: list,
            actorUserID: actorUserID,
            note: note
        )
    }

    @discardableResult
    func add(
        candidate: RestaurantCandidate,
        to list: RestaurantList,
        actorUserID: String,
        note: String = ""
    ) throws -> RestaurantListItem {
        let place = try place(for: candidate)
        return try add(
            place: place,
            localRestaurantID: nil,
            to: list,
            actorUserID: actorUserID,
            note: note
        )
    }

    @discardableResult
    func add(
        projection: DiscoveryRestaurantProjectionV1,
        to list: RestaurantList,
        actorUserID: String,
        localRestaurants: [Restaurant],
        note: String = ""
    ) throws -> RestaurantListItem {
        let local = LocalDiscoveryStore(context: context).localRestaurant(
            for: projection,
            among: localRestaurants
        )
        if let local { return try add(restaurant: local, to: list, actorUserID: actorUserID, note: note) }
        let referenceID = existingReferenceID(globalKey: projection.globalKey) ?? UUID().uuidString.lowercased()
        let place = try RestaurantListPlaceContractV1(
            globalKey: projection.globalKey,
            restaurantId: referenceID,
            placeIdentities: projection.placeIdentities.map {
                .init(provider: $0.provider, externalId: $0.externalId, isPrimary: $0.isPrimary)
            },
            name: projection.name,
            address: projection.address,
            city: projection.city,
            latitude: projection.latitude,
            longitude: projection.longitude,
            markerPhotoId: projection.photo?.photoId,
            merchantImageUrl: projection.merchantImageUrl,
            markerEmoji: projection.markerEmoji
        )
        return try add(place: place, localRestaurantID: nil, to: list, actorUserID: actorUserID, note: note)
    }

    @discardableResult
    func add(
        place: RestaurantListPlaceContractV1,
        localRestaurantID: UUID?,
        to list: RestaurantList,
        actorUserID: String,
        note: String = ""
    ) throws -> RestaurantListItem {
        try assertOwner(list, actorUserID: actorUserID)
        let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedNote.count <= 160 else { throw RestaurantListStoreError.noteTooLong }
        let all = try items(listID: list.id, includeDeleted: true)
        if all.contains(where: { $0.deletedAt == nil && $0.restaurantGlobalKey == place.globalKey }) {
            throw RestaurantListStoreError.duplicateRestaurant
        }
        let now = Date.now
        let position = (all.filter { $0.deletedAt == nil }.map(\.position).max() ?? -1) + 1
        let item: RestaurantListItem
        if let reusable = all.first(where: { $0.deletedAt != nil && $0.restaurantGlobalKey == place.globalKey }) {
            reusable.restaurantReferenceID = place.restaurantId
            reusable.localRestaurantID = localRestaurantID
            reusable.restaurantSnapshot = place
            reusable.position = position
            reusable.note = normalizedNote
            reusable.deletedAt = nil
            reusable.updatedAt = now
            reusable.syncStatus = .pending
            item = reusable
        } else {
            item = try RestaurantListItem(
                ownerUserID: actorUserID,
                listID: list.id,
                listRemoteID: list.remoteID ?? list.id.uuidString.lowercased(),
                restaurantReferenceID: place.restaurantId,
                localRestaurantID: localRestaurantID,
                restaurantGlobalKey: place.globalKey,
                restaurantSnapshot: place,
                position: position,
                note: normalizedNote,
                createdAt: now,
                updatedAt: now
            )
            context.insert(item)
        }
        try enqueue(item)
        try refreshSummary(list)
        try context.save()
        return item
    }

    func updateNote(_ item: RestaurantListItem, note: String, actorUserID: String) throws {
        guard item.ownerUserID == actorUserID else { throw RestaurantListStoreError.notOwner }
        let normalized = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count <= 160 else { throw RestaurantListStoreError.noteTooLong }
        item.note = normalized
        item.updatedAt = .now
        item.syncStatus = .pending
        try enqueue(item)
        try context.save()
    }

    func remove(_ item: RestaurantListItem, actorUserID: String) throws {
        guard item.ownerUserID == actorUserID else { throw RestaurantListStoreError.notOwner }
        let now = Date.now
        item.deletedAt = now
        item.updatedAt = now
        item.syncStatus = .pending
        try queue.enqueueDelete(
            entityType: .restaurantListItem,
            entityID: item.remoteID ?? item.id.uuidString.lowercased(),
            baseVersion: item.serverVersion,
            timestamp: now
        )
        guard let list = try lists(includeDeleted: true).first(where: { $0.id == item.listID }) else {
            throw RestaurantListStoreError.listNotFound
        }
        try compactPositions(listID: list.id, excluding: item.id)
        try refreshSummary(list)
        try context.save()
    }

    /// Reorders once after the drag/Edit transaction completes. Positions are
    /// deterministically renumbered 0...n-1; no request is emitted per drag pixel.
    func reorder(list: RestaurantList, orderedItemIDs: [UUID], actorUserID: String) throws {
        try assertOwner(list, actorUserID: actorUserID)
        let active = try items(listID: list.id, includeDeleted: false)
        guard Set(active.map(\.id)) == Set(orderedItemIDs), active.count == orderedItemIDs.count else {
            throw RestaurantListStoreError.invalidReorder
        }
        let byID = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        let now = Date.now
        for (position, id) in orderedItemIDs.enumerated() {
            guard let item = byID[id] else { throw RestaurantListStoreError.invalidReorder }
            guard item.position != position else { continue }
            item.position = position
            item.updatedAt = now
            item.syncStatus = .pending
            try enqueue(item)
        }
        try refreshSummary(list)
        try context.save()
    }

    func lists(ownerUserID: String? = nil, includeDeleted: Bool = false) throws -> [RestaurantList] {
        try lists(includeDeleted: includeDeleted).filter { ownerUserID == nil || $0.ownerUserID == ownerUserID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func items(listID: UUID, includeDeleted: Bool = false) throws -> [RestaurantListItem] {
        try context.fetch(FetchDescriptor<RestaurantListItem>())
            .filter { $0.listID == listID && (includeDeleted || $0.deletedAt == nil) }
            .sorted {
                if $0.position != $1.position { return $0.position < $1.position }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    func cache(
        summaries: [PublicListSummaryDTO],
        viewerUserID: String,
        ownerUserID: String,
        replace: Bool
    ) throws {
        let existing = try context.fetch(FetchDescriptor<CachedPublicRestaurantList>())
        let fetchedAt = Date.now
        if replace {
            let incoming = Set(summaries.map(\.id))
            for cached in existing where cached.viewerUserID == viewerUserID &&
                cached.ownerUserID == ownerUserID && !incoming.contains(cached.listID) {
                invalidate(listID: cached.listID, viewerUserID: viewerUserID)
            }
        }
        for summary in summaries {
            let cacheID = "\(viewerUserID)|\(summary.id)"
            if let cached = existing.first(where: { $0.cacheID == cacheID }) {
                cached.summaryData = try JSONEncoder().encode(summary)
                cached.fetchedAt = fetchedAt
            } else {
                context.insert(try CachedPublicRestaurantList(
                    viewerUserID: viewerUserID, summary: summary, fetchedAt: fetchedAt
                ))
            }
        }
        try context.save()
    }

    func cache(detail: PublicListDetailDTO, viewerUserID: String, replace: Bool) throws {
        try cache(
            summaries: [detail.list], viewerUserID: viewerUserID,
            ownerUserID: detail.list.owner.userId, replace: false
        )
        let existingLists = try context.fetch(FetchDescriptor<CachedPublicRestaurantList>())
        existingLists.first { $0.cacheID == "\(viewerUserID)|\(detail.list.id)" }?.detailValidatedAt = .now
        let existingItems = try context.fetch(FetchDescriptor<CachedPublicRestaurantListItem>())
        if replace {
            let incoming = Set(detail.items.map(\.id))
            for cached in existingItems where cached.viewerUserID == viewerUserID &&
                cached.listID == detail.list.id && !incoming.contains(cached.itemID) {
                context.delete(cached)
            }
        }
        for item in detail.items {
            let cacheID = "\(viewerUserID)|\(detail.list.id)|\(item.id)"
            if let cached = existingItems.first(where: { $0.cacheID == cacheID }) {
                cached.position = item.position
                cached.itemData = try JSONEncoder().encode(item)
                cached.fetchedAt = .now
            } else {
                context.insert(try CachedPublicRestaurantListItem(
                    viewerUserID: viewerUserID, listID: detail.list.id, item: item
                ))
            }
        }
        try context.save()
    }

    /// Removes all cached list projections for one owner/viewer pair. This is
    /// called when a friendship permission changes, while the server remains
    /// authoritative on every subsequent refresh.
    func invalidate(ownerUserID: String, viewerUserID: String) {
        let cached = (try? context.fetch(FetchDescriptor<CachedPublicRestaurantList>())) ?? []
        for list in cached where list.viewerUserID == viewerUserID && list.ownerUserID == ownerUserID {
            invalidate(listID: list.listID, viewerUserID: viewerUserID)
        }
    }

    func cachedSummaries(viewerUserID: String, ownerUserID: String) throws -> [PublicListSummaryDTO] {
        try context.fetch(FetchDescriptor<CachedPublicRestaurantList>())
            .filter { $0.viewerUserID == viewerUserID && $0.ownerUserID == ownerUserID }
            .compactMap(\.summary)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func cachedDetail(listID: String, viewerUserID: String) throws -> PublicListDetailDTO? {
        guard let list = try context.fetch(FetchDescriptor<CachedPublicRestaurantList>())
            .first(where: { $0.viewerUserID == viewerUserID && $0.listID == listID }),
              let summary = list.summary else { return nil }
        let items = try context.fetch(FetchDescriptor<CachedPublicRestaurantListItem>())
            .filter { $0.viewerUserID == viewerUserID && $0.listID == listID }
            .compactMap(\.item)
            .sorted { $0.position < $1.position }
        return PublicListDetailDTO(
            apiVersion: 1, list: summary, items: items,
            nextCursor: nil, generatedAt: SyncRecordMapper.dateString(list.fetchedAt)
        )
    }

    func invalidate(listID: String, viewerUserID: String) {
        if let list = try? context.fetch(FetchDescriptor<CachedPublicRestaurantList>())
            .first(where: { $0.viewerUserID == viewerUserID && $0.listID == listID }) {
            context.delete(list)
        }
        for item in (try? context.fetch(FetchDescriptor<CachedPublicRestaurantListItem>())) ?? []
        where item.viewerUserID == viewerUserID && item.listID == listID {
            context.delete(item)
        }
        try? context.save()
    }

    func purgePublicCache(viewerUserID: String? = nil) throws {
        for value in try context.fetch(FetchDescriptor<CachedPublicRestaurantList>())
        where viewerUserID == nil || value.viewerUserID == viewerUserID { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<CachedPublicRestaurantListItem>())
        where viewerUserID == nil || value.viewerUserID == viewerUserID { context.delete(value) }
        try context.save()
    }

    private func lists(includeDeleted: Bool) throws -> [RestaurantList] {
        try context.fetch(FetchDescriptor<RestaurantList>()).filter { includeDeleted || $0.deletedAt == nil }
    }

    private func enqueue(_ list: RestaurantList) throws {
        try queue.enqueueUpsert(
            entityType: .restaurantList,
            entityID: list.remoteID ?? list.id.uuidString.lowercased(),
            baseVersion: list.serverVersion,
            payload: SyncRecordMapper.restaurantListPayload(list),
            timestamp: list.updatedAt
        )
    }

    private func enqueue(_ item: RestaurantListItem) throws {
        try queue.enqueueUpsert(
            entityType: .restaurantListItem,
            entityID: item.remoteID ?? item.id.uuidString.lowercased(),
            baseVersion: item.serverVersion,
            payload: SyncRecordMapper.restaurantListItemPayload(item),
            timestamp: item.updatedAt
        )
    }

    private func assertOwner(_ list: RestaurantList, actorUserID: String) throws {
        guard list.ownerUserID == actorUserID else { throw RestaurantListStoreError.notOwner }
        guard list.deletedAt == nil else { throw RestaurantListStoreError.listNotFound }
    }

    private func compactPositions(listID: UUID, excluding: UUID) throws {
        let remaining = try items(listID: listID, includeDeleted: false).filter { $0.id != excluding }
        for (position, item) in remaining.enumerated() where item.position != position {
            item.position = position
            item.updatedAt = .now
            item.syncStatus = .pending
            try enqueue(item)
        }
    }

    private func refreshSummary(_ list: RestaurantList) throws {
        let active = try items(listID: list.id, includeDeleted: false)
        list.activeItemCount = active.count
        list.previewRestaurantIDs = active.prefix(4).map(\.restaurantGlobalKey)
        list.previewRestaurants = active.prefix(4).compactMap(\.restaurantSnapshot)
    }

    private func existingReferenceID(globalKey: String) -> String? {
        try? context.fetch(FetchDescriptor<RestaurantListItem>())
            .first(where: { $0.restaurantGlobalKey == globalKey })?.restaurantReferenceID
    }

    private func place(for restaurant: Restaurant) throws -> RestaurantListPlaceContractV1 {
        let record = try SyncRecordMapper.restaurantRecord(restaurant)
        let primary = record.placeIdentities.first(where: \.isPrimary) ?? record.placeIdentities[0]
        return try RestaurantListPlaceContractV1(
            globalKey: "\(primary.provider.rawValue):\(primary.externalId)",
            restaurantId: record.id,
            placeIdentities: record.placeIdentities.map {
                .init(provider: $0.provider, externalId: $0.externalId, isPrimary: $0.isPrimary)
            },
            name: record.name,
            address: record.address,
            city: record.city,
            latitude: record.latitude,
            longitude: record.longitude,
            markerPhotoId: record.markerPhotoId,
            merchantImageUrl: record.merchantImageUrl,
            markerEmoji: record.markerEmoji
        )
    }

    private func place(for candidate: RestaurantCandidate) throws -> RestaurantListPlaceContractV1 {
        let referenceID = UUID().uuidString.lowercased()
        let identity: RestaurantListPlaceIdentityContractV1
        let globalKey: String
        if let apple = candidate.appleMapItemIdentifier, !apple.isEmpty {
            identity = .init(provider: .appleMaps, externalId: apple, isPrimary: true)
            globalKey = "apple_maps:\(apple)"
        } else {
            let evidence = "\(candidate.name.lowercased())|\(candidate.address.lowercased())|\(candidate.latitude)|\(candidate.longitude)"
            let digest = SHA256.hash(data: Data(evidence.utf8)).map { String(format: "%02x", $0) }.joined()
            identity = .init(provider: .manual, externalId: "search:\(digest)", isPrimary: true)
            globalKey = "manual:search:\(digest)"
        }
        let reusedReference = existingReferenceID(globalKey: globalKey) ?? referenceID
        return try RestaurantListPlaceContractV1(
            globalKey: globalKey,
            restaurantId: reusedReference,
            placeIdentities: [identity],
            name: candidate.name,
            address: candidate.address,
            city: "",
            latitude: candidate.latitude,
            longitude: candidate.longitude,
            markerPhotoId: nil,
            merchantImageUrl: nil,
            markerEmoji: "🍽️"
        )
    }

    private static func normalized(title: String, description: String) throws -> (title: String, description: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 60 else { throw RestaurantListStoreError.invalidTitle }
        guard description.count <= 240 else { throw RestaurantListStoreError.descriptionTooLong }
        return (title, description)
    }
}
