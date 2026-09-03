import Foundation
import SwiftData

public struct TasteMapHybridRestaurantMetadata: Sendable {
    public let tags: [String]
    public let phone: String?
    public let openingHours: String?
    public let referencePrice: Double?
    public let localUserPhotoID: UUID?
    public let publicOrCachedPhotoID: String?
    public let providerMerchantImageURL: String?
    public let localUserPhotoVisitID: String?
    public let localUserPhotoVisibility: String?

    public init(
        tags: [String] = [],
        phone: String? = nil,
        openingHours: String? = nil,
        referencePrice: Double? = nil,
        localUserPhotoID: UUID? = nil,
        publicOrCachedPhotoID: String? = nil,
        providerMerchantImageURL: String? = nil,
        localUserPhotoVisitID: String? = nil,
        localUserPhotoVisibility: String? = nil
    ) {
        self.tags = tags
        self.phone = phone
        self.openingHours = openingHours
        self.referencePrice = referencePrice
        self.localUserPhotoID = localUserPhotoID
        self.publicOrCachedPhotoID = publicOrCachedPhotoID
        self.providerMerchantImageURL = providerMerchantImageURL
        self.localUserPhotoVisitID = localUserPhotoVisitID
        self.localUserPhotoVisibility = localUserPhotoVisibility
    }
}

public enum TasteMapHybridServiceError: Error, Sendable {
    case authRequired
    case profileMissing
    case restaurantMissing
    case invalidRequest
}

@MainActor
public protocol TasteMapHybridServiceProviding: AnyObject {
    var ownerUserID: String { get }
    func profileDashboard() throws -> TasteMapHybridProfileDTO
    func restaurantDetail(id: String) throws -> TasteMapHybridRestaurantDetailDTO
    func restaurants(request: TasteMapHybridRestaurantListRequest) throws -> [TasteMapHybridRestaurantDetailDTO]
    func mapViewport(request: TasteMapHybridMapBrowseRequest) throws -> TasteMapHybridMapBrowseResponse
    func contentSnapshot() throws -> TasteMapHybridContentSnapshotDTO
    func saveVisit(request: TasteMapHybridVisitWriteRequest) throws -> TasteMapHybridVisitMutationResultDTO
    func deleteVisit(id: String) throws -> TasteMapHybridVisitMutationResultDTO
}

/// Typed, owner-scoped read facade for the first Hybrid-ready routes.
///
/// It consumes the existing SwiftData container and emits stable DTOs. It does
/// not expose SwiftData models, credentials, local file paths, mutation queue
/// internals, or the caller-selected owner to JavaScript.
@MainActor
public final class TasteMapHybridBridgeService: TasteMapHybridServiceProviding {
    public let ownerUserID: String

    private let context: ModelContext
    private let membershipTier: String
    private let mapSharingEnabled: Bool
    private let metadataByRestaurantID: [UUID: TasteMapHybridRestaurantMetadata]
    private let enqueueSharedMealInvitations: ((String, [String]) throws -> Void)?
    private let attachPendingPhotos: ((
        [TasteMapHybridPendingPhotoAttachmentDTO], UUID, UUID, [String: String], String
    ) -> Int)?
    /// Owner-scoped DTO projection cache. SwiftData remains authoritative and
    /// every write invalidates this cache before another read can observe it.
    private var projectedRestaurantSnapshot: [TasteMapHybridRestaurantDTO]?
#if DEBUG
    var projectedRestaurantSnapshotBuildCount = 0

    private var usesDeterministicVisualFixture: Bool {
#if TASTEMAP_HYBRID_BRIDGE_CORE
        ownerUserID == TasteMapHybridDebugFixture.ownerUserID
#else
        ownerUserID == TasteMapHybridDebugFixture.ownerUserID || TasteMapUITestFixtures.usesVisualQA
#endif
    }
#endif

    public init(
        container: ModelContainer,
        ownerUserID: String,
        membershipTier: String = "free",
        mapSharingEnabled: Bool = false,
        metadataByRestaurantID: [UUID: TasteMapHybridRestaurantMetadata] = [:],
        enqueueSharedMealInvitations: ((String, [String]) throws -> Void)? = nil,
        attachPendingPhotos: ((
            [TasteMapHybridPendingPhotoAttachmentDTO], UUID, UUID, [String: String], String
        ) -> Int)? = nil
    ) throws {
        let normalizedOwner = LocalAccountOwner.normalized(ownerUserID)
        guard normalizedOwner.hasPrefix("tm_") else { throw TasteMapHybridServiceError.authRequired }
        self.ownerUserID = normalizedOwner
        self.context = ModelContext(container)
        self.context.autosaveEnabled = false
        self.membershipTier = membershipTier == "member" ? "member" : "free"
        self.mapSharingEnabled = mapSharingEnabled
        self.metadataByRestaurantID = metadataByRestaurantID
        self.enqueueSharedMealInvitations = enqueueSharedMealInvitations
        self.attachPendingPhotos = attachPendingPhotos
    }

    public func profileDashboard() throws -> TasteMapHybridProfileDTO {
        guard let profile = try context.fetch(FetchDescriptor<UserProfile>()).first(where: {
            $0.tasteMapUserID == ownerUserID && $0.deletedAt == nil
        }) else { throw TasteMapHybridServiceError.profileMissing }

        let restaurants = try scopedRestaurants()
        let follows = try context.fetch(FetchDescriptor<CachedFollow>()).filter {
            $0.currentUserID == ownerUserID && $0.deletedAt == nil
        }
        return TasteMapHybridProfileDTO(
            user: TasteMapHybridUserDTO(
                id: profile.tasteMapUserID,
                nickname: profile.displayName,
                bio: profile.bio,
                city: profile.city,
                avatarPhotoId: profile.avatarPhotoID,
                avatarPresetId: profile.avatarPreset.rawValue,
                membershipTier: membershipTier,
                mapSharingEnabled: mapSharingEnabled,
                mapVisibility: profile.visibility.rawValue,
                createdAt: Self.dateFormatter.string(from: profile.createdAt),
                updatedAt: Self.dateFormatter.string(from: profile.updatedAt)
            ),
            restaurants: restaurants,
            followerCount: follows.filter { $0.followedUserID == ownerUserID }.count,
            followingCount: follows.filter { $0.followerUserID == ownerUserID }.count
        )
    }

    public func restaurantDetail(id: String) throws -> TasteMapHybridRestaurantDetailDTO {
        // A Restaurant may have become owner-scoped through another existing
        // Native service (for example Add to Want-to-Go) since this detail was
        // last projected. Detail navigation is a refresh boundary; rebuild the
        // owner snapshot so a public read cannot retain stale capabilities.
        projectedRestaurantSnapshot = nil
        let scoped = try scopedRestaurants()
        if let restaurant = scoped.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) {
            return try ownedDetail(restaurant)
        }
#if !TASTEMAP_HYBRID_BRIDGE_CORE
        if let reference = try TasteMapHybridRestaurantReferenceResolver.resolve(
            identifier: id,
            ownerUserID: ownerUserID,
            context: context
        ) {
            let ownedModels = try context.fetch(FetchDescriptor<Restaurant>()).filter {
                $0.ownerUserID == ownerUserID && $0.deletedAt == nil
            }
            if let match = RestaurantDeduplicator.classifiedMatch(
                for: reference.projection.restaurantCandidate,
                in: ownedModels
            ), match.kind == .exactProviderIdentity {
                let local = match.restaurant
                let localID = local.remoteID ?? local.id.uuidString.lowercased()
                if let restaurant = scoped.first(where: { $0.id.caseInsensitiveCompare(localID) == .orderedSame }) {
                    return try ownedDetail(restaurant)
                }
            }
            return try publicDetail(reference)
        }
#endif
        throw TasteMapHybridServiceError.restaurantMissing
    }

    public func restaurants(request: TasteMapHybridRestaurantListRequest) throws -> [TasteMapHybridRestaurantDetailDTO] {
        let allowedIDs = request.ids.map { Set($0.map { $0.lowercased() }) }
        let maximum = min(max(request.limit ?? 500, 0), 500)
        return try scopedRestaurants()
            .filter { restaurant in
                (allowedIDs == nil || allowedIDs?.contains(restaurant.id.lowercased()) == true)
                    && (request.status == nil || request.status == restaurant.status)
            }
            .prefix(maximum)
            .map { restaurant in
                TasteMapHybridRestaurantDetailDTO(
                    restaurant: restaurant,
                    socialStats: nil,
                    viewerState: restaurant.status == "visited" ? "visited" : "want_to_go",
                    editableVisitIDs: restaurant.visits.map(\.id),
                    capabilities: .owned
                )
            }
    }

    private func ownedDetail(_ restaurant: TasteMapHybridRestaurantDTO) throws -> TasteMapHybridRestaurantDetailDTO {
        TasteMapHybridRestaurantDetailDTO(
            restaurant: restaurant,
            socialStats: try socialStats(for: restaurant),
            viewerState: restaurant.status == "visited" ? "visited" : "want_to_go",
            editableVisitIDs: restaurant.visits.map(\.id),
            capabilities: .owned
        )
    }

#if !TASTEMAP_HYBRID_BRIDGE_CORE
    private func publicDetail(
        _ reference: TasteMapHybridResolvedRestaurantReference
    ) throws -> TasteMapHybridRestaurantDetailDTO {
        let value = reference.projection
        let timestamp = Self.dateFormatter.string(from: reference.updatedAt)
        let status = reference.viewerState == .visited ? "visited" : "wantToGo"
        let restaurant = TasteMapHybridRestaurantDTO(
            id: value.globalKey,
            name: value.name,
            address: value.address,
            city: value.city,
            latitude: value.latitude,
            longitude: value.longitude,
            status: status,
            tags: value.tags,
            phone: nil,
            openingHours: nil,
            referencePrice: value.pricePerPerson,
            visitCount: 0,
            averageRating: nil,
            scoreOutOfTen: nil,
            latestVisitDate: nil,
            createdAt: timestamp,
            updatedAt: timestamp,
            visits: [],
            image: publicUGCOrCategoryDescriptor(photo: value.photo, seed: value.globalKey, name: value.name, tags: value.tags)
        )
        return TasteMapHybridRestaurantDetailDTO(
            restaurant: restaurant,
            socialStats: try socialStats(globalIdentityKeys: [value.globalKey]),
            viewerState: reference.viewerState.rawValue,
            editableVisitIDs: [],
            capabilities: .publicReadable
        )
    }
#endif

    private func socialStats(
        for restaurant: TasteMapHybridRestaurantDTO
    ) throws -> TasteMapHybridRestaurantSocialStatsDTO? {
#if DEBUG
        if usesDeterministicVisualFixture {
            return Self.debugSocialStats(restaurantID: restaurant.id)
        }
#endif
#if !TASTEMAP_HYBRID_BRIDGE_CORE
        guard let model = try ownedRestaurantIfPresent(identifier: restaurant.id) else { return nil }
        return try socialStats(globalIdentityKeys: RestaurantDetailMetadata(restaurant: model).globalIdentityKeys)
#else
        return nil
#endif
    }

#if !TASTEMAP_HYBRID_BRIDGE_CORE
    private func socialStats(
        globalIdentityKeys: Set<String>
    ) throws -> TasteMapHybridRestaurantSocialStatsDTO? {
        guard !globalIdentityKeys.isEmpty else { return nil }
        let ratings = try context.fetch(FetchDescriptor<CachedDiscoveryPlacement>())
            .filter {
                $0.currentUserID == ownerUserID && globalIdentityKeys.contains($0.globalKey)
            }
            .sorted { $0.generatedAt > $1.generatedAt }
            .compactMap(\.context)
            .first?
            .ratings
        guard let ratings else { return nil }
        let result = TasteMapHybridRestaurantSocialStatsDTO(
            overallUserRating: ratings.community.value.map { $0 * 2 },
            overallUserCount: ratings.community.sampleCount,
            friendAverageRating: ratings.friends.value.map { $0 * 2 },
            friendUserCount: ratings.friends.sampleCount,
            similarTasteAverageRating: ratings.similarTaste.value.map { $0 * 2 },
            similarTasteUserCount: ratings.similarTaste.sampleCount,
            repeatVisitRate: nil,
            repeatVisitorCount: 0,
            uniqueVisitorCount: ratings.community.sampleCount
        )
        guard result.overallUserRating != nil || result.friendAverageRating != nil
                || result.similarTasteAverageRating != nil else { return nil }
        return result
    }
#endif

#if DEBUG
    private static func debugSocialStats(
        restaurantID: String
    ) -> TasteMapHybridRestaurantSocialStatsDTO {
        let seed = restaurantID.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return TasteMapHybridRestaurantSocialStatsDTO(
            overallUserRating: 8.3 + Double(seed % 5) * 0.1,
            overallUserCount: 24 + seed % 17,
            friendAverageRating: 9.1 + Double(seed % 4) * 0.1,
            friendUserCount: 7 + seed % 6,
            similarTasteAverageRating: 8.8 + Double(seed % 3) * 0.1,
            similarTasteUserCount: 11 + seed % 8,
            repeatVisitRate: Double(32 + seed % 29),
            repeatVisitorCount: 6 + seed % 7,
            uniqueVisitorCount: 24 + seed % 17
        )
    }
#endif

    public func mapViewport(request: TasteMapHybridMapBrowseRequest) throws -> TasteMapHybridMapBrowseResponse {
        guard request.requestID.count >= 8, request.requestID.count <= 128 else {
            throw TasteMapHybridServiceError.invalidRequest
        }
        let all = try scopedRestaurants()
        let options = TasteMapHybridMapBrowseOptions(
            cities: stableValues(all.map(\.city)),
            companions: stableValues(all.flatMap { $0.visits.flatMap(\.companions) }),
            cuisines: stableValues(all.flatMap(\.tags)),
            recommendationSources: stableValues(all.flatMap { $0.visits.map(\.recommendationSourceText) })
        )
        let normalizedSearch = request.search.trimmingCharacters(in: .whitespacesAndNewlines).folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        let recommendationSource: [TasteMapHybridRestaurantDTO]
#if DEBUG
        // The isolated Hybrid Visual QA owner carries deterministic
        // recommendation fixtures so performance is measured against a real
        // content state. Shipping owners never synthesize personal results.
        if usesDeterministicVisualFixture {
            recommendationSource = Array(all.filter { $0.status == "visited" }.sorted {
                if $0.scoreOutOfTen != $1.scoreOutOfTen {
                    return ($0.scoreOutOfTen ?? -1) > ($1.scoreOutOfTen ?? -1)
                }
                return $0.id < $1.id
            }.prefix(18))
        } else {
            recommendationSource = []
        }
#else
        recommendationSource = []
#endif
        func filteredValues(
            for scope: TasteMapHybridMapScope,
            includeBounds: Bool
        ) -> [TasteMapHybridRestaurantDTO] {
            let source = scope == .recommended ? recommendationSource : all
            let desiredStatus = scope == .wantToGo ? "wantToGo" : "visited"
            return source.filter { item in
                guard item.status == desiredStatus else { return false }
                if includeBounds, let bounds = request.bounds, !Self.contains(item, in: bounds) { return false }
                if let city = nonempty(request.filters.city), item.city != city { return false }
                if let score = request.filters.minimumScoreOutOfTen, (item.scoreOutOfTen ?? -1) < score { return false }
                if let spend = request.filters.maximumSpend, (item.referencePrice ?? .greatestFiniteMagnitude) > spend { return false }
                if let visits = request.filters.minimumVisitCount, item.visitCount < visits { return false }
                if let cuisine = nonempty(request.filters.cuisine), !item.tags.contains(cuisine) { return false }
                if let companion = nonempty(request.filters.companion),
                   !item.visits.contains(where: { $0.companions.contains(companion) }) { return false }
                if let source = nonempty(request.filters.recommendationSource),
                   !item.visits.contains(where: { $0.recommendationSourceText == source }) { return false }
                guard !normalizedSearch.isEmpty else { return true }
                return ([item.name, item.city, item.address] + item.tags)
                    .joined(separator: "\n")
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .contains(normalizedSearch)
            }
        }
        func scopeTotal(_ scope: TasteMapHybridMapScope) -> Int {
            let source = scope == .recommended ? recommendationSource : all
            let desiredStatus = scope == .wantToGo ? "wantToGo" : "visited"
            return source.filter { $0.status == desiredStatus }.count
        }
        let scopeCounts = TasteMapHybridMapScopeCounts(
            visited: scopeTotal(.visited),
            wantToGo: scopeTotal(.wantToGo),
            recommended: scopeTotal(.recommended)
        )
        var values = filteredValues(for: request.scope, includeBounds: true)
        values.sort { left, right in
            switch request.sort {
            case .rating:
                if left.scoreOutOfTen != right.scoreOutOfTen { return (left.scoreOutOfTen ?? -1) > (right.scoreOutOfTen ?? -1) }
            case .visits:
                if left.visitCount != right.visitCount { return left.visitCount > right.visitCount }
            case .distance:
                if let origin = request.currentLocation {
                    let leftDistance = Self.squaredDistance(left, from: origin)
                    let rightDistance = Self.squaredDistance(right, from: origin)
                    if leftDistance != rightDistance { return leftDistance < rightDistance }
                }
            case .recent:
                if left.latestVisitDate != right.latestVisitDate {
                    return (left.latestVisitDate ?? left.createdAt) > (right.latestVisitDate ?? right.createdAt)
                }
            }
            return left.id < right.id
        }
        let totalCount = values.count
        let maximum = min(max(request.limit ?? 300, 0), 500)
        return TasteMapHybridMapBrowseResponse(
            requestID: request.requestID,
            items: Array(values.prefix(maximum)),
            totalCount: totalCount,
            scopeCounts: scopeCounts,
            options: options
        )
    }

    public func contentSnapshot() throws -> TasteMapHybridContentSnapshotDTO {
        let generatedAt = Self.dateFormatter.string(from: .now)
        let restaurants = try scopedRestaurants()
        if ownerUserID == "tm_hybrid_debug" {
            return debugContentSnapshot(restaurants: restaurants, generatedAt: generatedAt)
        }
#if !TASTEMAP_HYBRID_BRIDGE_CORE && DEBUG
        // Visual QA is an isolated Debug-only session. It intentionally uses
        // deterministic owner-scoped records instead of remote social APIs so
        // Lafayette can inspect rich content without a real Apple credential.
        if TasteMapUITestFixtures.usesVisualQA {
            return debugContentSnapshot(restaurants: restaurants, generatedAt: generatedAt)
        }
#endif
#if TASTEMAP_HYBRID_BRIDGE_CORE
        return TasteMapHybridContentSnapshotDTO(
            generatedAt: generatedAt,
            discovery: .init(forYou: [], similarTaste: [], trending: []),
            community: .init(following: [], latest: []),
            lists: []
        )
#else
        let discoveryRestaurants = Dictionary(uniqueKeysWithValues:
            try context.fetch(FetchDescriptor<CachedDiscoveryRestaurant>())
                .filter { $0.currentUserID == ownerUserID }
                .compactMap { cached in cached.projection.map { (cached.globalKey, $0) } }
        )
        let discoveryItems = try context.fetch(FetchDescriptor<CachedDiscoveryPlacement>())
            .filter { $0.currentUserID == ownerUserID }
            .compactMap { placement -> TasteMapHybridDiscoveryItemDTO? in
                guard let projection = discoveryRestaurants[placement.globalKey],
                      let value = placement.context else { return nil }
                return discoveryDTO(context: value, restaurant: projection)
            }
            .reduce(into: [String: TasteMapHybridDiscoveryItemDTO]()) { result, item in
                if result[item.id] == nil || (result[item.id]?.rank ?? .max) > item.rank { result[item.id] = item }
            }
            .values
            .sorted { $0.rank < $1.rank || ($0.rank == $1.rank && $0.id < $1.id) }

        let cachedCommunity = try context.fetch(FetchDescriptor<CachedCommunityContent>())
            .filter { $0.currentUserID == ownerUserID }
        let latest = uniqueCommunityItems(cachedCommunity.compactMap { $0.item }.map(communityDTO))
        let followingIDs = Set(cachedCommunity.filter {
            $0.routeKey == LocalCommunityStore.feedRoute(.following)
        }.map(\.contentID))

        let profile = try context.fetch(FetchDescriptor<UserProfile>()).first {
            $0.tasteMapUserID == ownerUserID && $0.deletedAt == nil
        }
        let ownerName = profile?.displayName ?? "我"
        let ownLists = try context.fetch(FetchDescriptor<RestaurantList>())
            .filter { $0.ownerUserID == ownerUserID && $0.deletedAt == nil }
        let ownItems = try context.fetch(FetchDescriptor<RestaurantListItem>())
            .filter { $0.ownerUserID == ownerUserID && $0.deletedAt == nil }
        let ownListDTOs = ownLists.map { list in
            let items = ownItems.filter { $0.listID == list.id }.sorted { $0.position < $1.position }
            return TasteMapHybridListDTO(
                id: list.remoteID ?? list.id.uuidString.lowercased(),
                title: list.title,
                description: list.listDescription,
                visibility: list.visibility.rawValue,
                isRanked: list.isRanked,
                isOwnedByViewer: true,
                ownerName: ownerName,
                restaurantCount: items.count,
                restaurants: items.compactMap { listRestaurantDTO(item: $0) },
                updatedAt: Self.dateFormatter.string(from: list.updatedAt)
            )
        }
        let publicLists = try context.fetch(FetchDescriptor<CachedPublicRestaurantList>())
            .filter { $0.viewerUserID == ownerUserID }
        let publicItems = try context.fetch(FetchDescriptor<CachedPublicRestaurantListItem>())
            .filter { $0.viewerUserID == ownerUserID }
        let publicListDTOs = publicLists.compactMap { cached -> TasteMapHybridListDTO? in
            guard let summary = cached.summary else { return nil }
            let items = publicItems.filter { $0.listID == cached.listID }.compactMap(\.item).sorted { $0.position < $1.position }
            return TasteMapHybridListDTO(
                id: summary.id,
                title: summary.title,
                description: summary.description,
                visibility: summary.visibility.rawValue,
                isRanked: summary.isRanked,
                isOwnedByViewer: summary.owner.userId == ownerUserID,
                ownerName: summary.owner.displayName,
                restaurantCount: summary.restaurantCount,
                restaurants: items.map { item in listRestaurantDTO(item: item) },
                updatedAt: summary.updatedAt
            )
        }
        return TasteMapHybridContentSnapshotDTO(
            generatedAt: generatedAt,
            discovery: .init(
                forYou: discoveryItems.filter { $0.mode == "for_you" },
                similarTaste: discoveryItems.filter { $0.mode == "similar_taste" },
                trending: discoveryItems.filter { $0.mode == "trending" }
            ),
            community: .init(
                following: latest.filter { followingIDs.contains($0.id) },
                latest: latest
            ),
            lists: (ownListDTOs + publicListDTOs).sorted { $0.updatedAt > $1.updatedAt }
        )
#endif
    }

    public func saveVisit(
        request: TasteMapHybridVisitWriteRequest
    ) throws -> TasteMapHybridVisitMutationResultDTO {
#if TASTEMAP_HYBRID_BRIDGE_CORE
        // The standalone contract package intentionally excludes the App's
        // persistence services. Shipping builds use the owner-scoped write
        // implementation below; contract tests must never grow a second store.
        throw TasteMapHybridServiceError.invalidRequest
#else
        let restaurant: Restaurant?
        let candidate: RestaurantCandidate?
        let existingVisit: Visit?
        if let visitID = request.visitID {
            let value = try ownedVisit(identifier: visitID)
            let owned = try ownedRestaurant(localID: value.restaurantId)
            guard Self.matchesRestaurantIdentifier(request.restaurantID, restaurant: owned) else {
                throw TasteMapHybridServiceError.invalidRequest
            }
            restaurant = owned
            candidate = nil
            existingVisit = value
        } else if let owned = try ownedRestaurantIfPresent(identifier: request.restaurantID) {
            restaurant = owned
            candidate = nil
            existingVisit = nil
        } else {
            guard let reference = try TasteMapHybridRestaurantReferenceResolver.resolve(
                identifier: request.restaurantID,
                ownerUserID: ownerUserID,
                context: context
            ) else { throw TasteMapHybridServiceError.restaurantMissing }
            restaurant = nil
            candidate = reference.projection.restaurantCandidate
            existingVisit = nil
        }
        let allRestaurants = try context.fetch(FetchDescriptor<Restaurant>()).filter {
            $0.ownerUserID == ownerUserID && $0.deletedAt == nil
        }
        let allDishes = try context.fetch(FetchDescriptor<Dish>()).filter {
            $0.ownerUserID == ownerUserID && $0.deletedAt == nil
        }
        let dishDrafts = request.draft.dishes.map { value in
            let existingDish = allDishes.first { dish in
                dish.remoteID?.caseInsensitiveCompare(value.id) == .orderedSame
                    || dish.id.uuidString.caseInsensitiveCompare(value.id) == .orderedSame
            }
            return DishDraft(
                id: UUID(uuidString: value.id) ?? UUID(),
                dishID: existingDish?.id,
                name: value.name,
                taste: value.taste,
                rating: value.rating,
                price: value.price.map { Decimal($0) },
                photoID: value.photoID.flatMap(UUID.init(uuidString:))
            )
        }
        let result = try LocalVisitRecordingStore(context: context).commit(
            restaurant: restaurant,
            candidate: candidate,
            existingVisit: existingVisit,
            allRestaurants: allRestaurants,
            draft: try visitDraft(request.draft),
            dishDrafts: dishDrafts,
            actorUserID: ownerUserID
        )
        if !request.draft.sharedParticipantUserIDs.isEmpty,
           let sourceVisitID = result.visit.remoteID {
            try enqueueSharedMealInvitations?(
                sourceVisitID,
                request.draft.sharedParticipantUserIDs
            )
        }
        let photoFailureCount = attachPendingPhotos?(
            request.draft.pendingPhotos ?? [],
            result.restaurant.id,
            result.visit.id,
            Dictionary(uniqueKeysWithValues: result.dishesByDraftID.map {
                ($0.key.uuidString.lowercased(), $0.value.id.uuidString.lowercased())
            }),
            request.draft.visibility
        ) ?? 0
        projectedRestaurantSnapshot = nil
        return TasteMapHybridVisitMutationResultDTO(
            restaurantID: result.restaurant.remoteID ?? result.restaurant.id.uuidString.lowercased(),
            visitID: result.visit.remoteID ?? result.visit.id.uuidString.lowercased(),
            updatedAt: Self.dateFormatter.string(from: result.visit.updatedAt),
            photoWarning: photoFailureCount > 0
                ? "到访已保存，但有 \(photoFailureCount) 张照片未能附加。"
                : nil
        )
#endif
    }

    public func deleteVisit(id: String) throws -> TasteMapHybridVisitMutationResultDTO {
#if TASTEMAP_HYBRID_BRIDGE_CORE
        throw TasteMapHybridServiceError.invalidRequest
#else
        let visit = try ownedVisit(identifier: id)
        let restaurant = try ownedRestaurant(localID: visit.restaurantId)
        try LocalTasteMapStore(context: context).delete(visit, actorUserID: ownerUserID)
        projectedRestaurantSnapshot = nil
        return TasteMapHybridVisitMutationResultDTO(
            restaurantID: restaurant.remoteID ?? restaurant.id.uuidString.lowercased(),
            visitID: visit.remoteID ?? visit.id.uuidString.lowercased(),
            updatedAt: Self.dateFormatter.string(from: visit.updatedAt)
        )
#endif
    }

#if !TASTEMAP_HYBRID_BRIDGE_CORE
    private func visitDraft(_ value: TasteMapHybridVisitWriteDraftDTO) throws -> VisitDraft {
        guard let visitedAt = Self.dateFormatter.date(from: value.visitedAt),
              let diningMode = DiningMode(rawValue: value.diningMode),
              let visibility = VisitVisibility(rawValue: value.visibility) else {
            throw TasteMapHybridServiceError.invalidRequest
        }
        return VisitDraft(
            visitedAt: visitedAt,
            diningMode: diningMode,
            partySize: value.partySize,
            rating: value.rating,
            valueRating: value.valueRating,
            environmentRating: value.environmentRating,
            serviceRating: value.serviceRating,
            myActualSpend: value.myActualSpend.map { Decimal($0) },
            totalPrice: value.totalPrice.map { Decimal($0) },
            visibility: visibility,
            paymentMode: value.paymentMode.flatMap(VisitPaymentMode.init(rawValue:)),
            queueDuration: value.queueDuration.flatMap(VisitQueueDuration.init(rawValue:)),
            diningOccasions: value.diningOccasions.compactMap(VisitDiningOccasion.init(rawValue:)),
            diningOccasionText: value.diningOccasionText,
            valueTags: value.valueTags,
            environmentTags: value.environmentTags,
            serviceTags: value.serviceTags,
            noiseLevel: value.noiseLevel.flatMap(VisitNoiseLevel.init(rawValue:)),
            diningDuration: value.diningDuration.flatMap(VisitDiningDuration.init(rawValue:)),
            portionLevel: value.portionLevel.flatMap(VisitPortionLevel.init(rawValue:)),
            transportConvenience: value.transportConvenience.flatMap(VisitTransportConvenience.init(rawValue:)),
            specialNotes: value.specialNotes,
            companionIDs: [],
            companionNames: value.companions,
            recommendationSourceType: value.recommendationSourceType.flatMap(RecommendationSourceType.init(rawValue:)),
            recommendationSourceUserID: value.recommendationSourceUserID,
            recommendationSourceText: value.recommendationSourceText,
            sharedMealID: nil,
            note: value.note
        )
    }

    private func ownedRestaurant(identifier: String) throws -> Restaurant {
        guard let value = try ownedRestaurantIfPresent(identifier: identifier) else {
            throw TasteMapHybridServiceError.restaurantMissing
        }
        return value
    }

    private func ownedRestaurantIfPresent(identifier: String) throws -> Restaurant? {
        try context.fetch(FetchDescriptor<Restaurant>()).first(where: {
            $0.ownerUserID == ownerUserID && $0.deletedAt == nil
                && Self.matchesRestaurantIdentifier(identifier, restaurant: $0)
        })
    }

    private static func matchesRestaurantIdentifier(_ identifier: String, restaurant: Restaurant) -> Bool {
        restaurant.remoteID?.caseInsensitiveCompare(identifier) == .orderedSame
            || restaurant.id.uuidString.caseInsensitiveCompare(identifier) == .orderedSame
    }

    private func ownedRestaurant(localID: UUID) throws -> Restaurant {
        guard let value = try context.fetch(FetchDescriptor<Restaurant>()).first(where: {
            $0.id == localID && $0.ownerUserID == ownerUserID && $0.deletedAt == nil
        }) else { throw TasteMapHybridServiceError.restaurantMissing }
        return value
    }

    private func ownedVisit(identifier: String) throws -> Visit {
        guard let value = try context.fetch(FetchDescriptor<Visit>()).first(where: {
            $0.ownerUserID == ownerUserID && $0.deletedAt == nil
                && ($0.remoteID?.caseInsensitiveCompare(identifier) == .orderedSame
                    || $0.id.uuidString.caseInsensitiveCompare(identifier) == .orderedSame)
        }) else { throw TasteMapHybridServiceError.invalidRequest }
        return value
    }
#endif

    private func debugContentSnapshot(
        restaurants: [TasteMapHybridRestaurantDTO],
        generatedAt: String
    ) -> TasteMapHybridContentSnapshotDTO {
        let names = ["林夏", "周舟", "陈一碗", "江南胃", "阿岚", "西湖小柚", "陆小满", "一只饭团"]
        func person(_ index: Int, city: String) -> TasteMapHybridPersonDTO {
            TasteMapHybridPersonDTO(
                id: "tm_demo_\(index)", name: names[index % names.count], city: city,
                avatarPhotoID: nil, avatarPresetID: ["otter", "polar-bear", "fox", "capybara"][index % 4],
                isFollowing: index.isMultiple(of: 2)
            )
        }
        let discovery = Array(restaurants.prefix(12).enumerated()).map { index, value in
            let user = person(index, city: value.city)
            let fixtureRating = index == 3 ? nil : max(3.5, 4.5 - Double(index) * 0.1)
            let activityRating = value.averageRating ?? fixtureRating
            let communityRating = activityRating.map { max(0, $0 - 0.05) }
            let ratingSampleCount = communityRating == nil ? 0 : max(10, value.visitCount)
            let original = contentRestaurant(value)
            let content = index == 0 ? original : replacingImage(
                original,
                with: index.isMultiple(of: 2)
                    ? debugCategoryDescriptor(name: value.name, tags: value.tags, seed: value.id)
                    : debugUGCDescriptor(value: value, ownerID: person(index, city: value.city).id, kind: .publicUGC)
            )
            return TasteMapHybridDiscoveryItemDTO(
                id: "hybrid-discovery-\(index)", mode: "for_you", restaurant: content,
                viewerState: index == 0 ? "none" : index == 1 ? "want_to_go" : value.status == "visited" ? "visited" : "want_to_go", sourceUser: nil,
                activityRating: nil, activityVisitedAt: nil,
                interaction: .init(
                    activityID: nil, visitID: "demo-visit-\(index)",
                    authorID: user.id, restaurantID: content.id
                ),
                likedByViewer: index == 1, likeCount: 12 + index * 5, commentCount: 2 + index,
                communityRating: .init(valueOutOfFive: communityRating, sampleCount: ratingSampleCount),
                reason: index.isMultiple(of: 2) ? "与你常吃的菜系很接近" : "同城高质量真实记录",
                similarityPercent: 82 - index * 3, sharedRestaurantCount: 6 + index,
                uniqueVisitorCount: 18 + index * 4, wantToGoCount: 9 + index,
                rank: index + 1
            )
        }
        let similar = discovery.enumerated().map { index, item in
            let user = person(index, city: item.restaurant.city)
            let visual = index.isMultiple(of: 2)
                ? debugUGCDescriptor(value: restaurants[index], ownerID: user.id, kind: .activityPhoto)
                : debugCategoryDescriptor(name: item.restaurant.name, tags: item.restaurant.tags, seed: item.restaurant.id)
            return TasteMapHybridDiscoveryItemDTO(
                id: "similar-\(item.id)", mode: "similar_taste", restaurant: replacingImage(item.restaurant, with: visual),
                viewerState: item.viewerState, sourceUser: user,
                activityRating: restaurants[index].averageRating,
                activityVisitedAt: restaurants[index].latestVisitDate ?? generatedAt,
                interaction: item.interaction, likedByViewer: item.likedByViewer,
                likeCount: item.likeCount, commentCount: item.commentCount,
                communityRating: item.communityRating,
                reason: "与这位用户有 \(item.sharedRestaurantCount ?? 0) 家共同到访",
                similarityPercent: item.similarityPercent, sharedRestaurantCount: item.sharedRestaurantCount,
                uniqueVisitorCount: nil, wantToGoCount: nil, rank: item.rank
            )
        }
        let trending = discovery.enumerated().map { index, item in
            let visual = index.isMultiple(of: 2)
                ? debugUGCDescriptor(value: restaurants[index], ownerID: person(index, city: item.restaurant.city).id, kind: .publicUGC)
                : debugCategoryDescriptor(name: item.restaurant.name, tags: item.restaurant.tags, seed: item.restaurant.id)
            return TasteMapHybridDiscoveryItemDTO(
                id: "trending-\(item.id)", mode: "trending", restaurant: replacingImage(item.restaurant, with: visual),
                viewerState: item.viewerState, sourceUser: nil,
                activityRating: nil, activityVisitedAt: nil,
                interaction: item.interaction, likedByViewer: item.likedByViewer,
                likeCount: item.likeCount, commentCount: item.commentCount,
                communityRating: item.communityRating,
                reason: "最近 7 天有 \(item.uniqueVisitorCount ?? 0) 位用户到访",
                similarityPercent: nil, sharedRestaurantCount: nil,
                uniqueVisitorCount: item.uniqueVisitorCount, wantToGoCount: item.wantToGoCount, rank: item.rank
            )
        }
        let activities = discovery.enumerated().map { index, item in
            let user = person(index, city: item.restaurant.city)
            let visual = index.isMultiple(of: 2)
                ? debugUGCDescriptor(value: restaurants[index], ownerID: user.id, kind: .activityPhoto)
                : debugCategoryDescriptor(name: item.restaurant.name, tags: item.restaurant.tags, seed: item.restaurant.id)
            return TasteMapHybridActivityItemDTO(
                id: "hybrid-activity-\(index)", kind: index % 5 == 4 ? "want_to_go" : "visit",
                eventAt: restaurants[index].latestVisitDate ?? generatedAt,
                user: user, restaurant: replacingImage(item.restaurant, with: visual),
                visitID: index % 5 == 4 ? nil : "demo-visit-\(index)",
                interaction: index % 5 == 4 ? nil : .init(
                    activityID: "hybrid-activity-\(index)", visitID: "demo-visit-\(index)",
                    authorID: user.id, restaurantID: item.restaurant.id
                ),
                visitRating: index % 5 == 4 ? nil : restaurants[index].averageRating,
                note: index % 5 == 4 ? nil : ["值得专程来吃，服务也很细致。", "今天最惊喜的是招牌菜。", "和朋友一起吃很舒服。", "会为了这道菜再来一次。"][index % 4],
                viewerState: item.viewerState, likedByViewer: index == 1,
                likeCount: 12 + index * 5, commentCount: 2 + index
            )
        }
        let lists = (0..<5).map { index in
            let values = restaurants.enumerated().filter { $0.offset % 5 == index }.map { pair in
                TasteMapHybridListRestaurantDTO(
                    id: pair.element.id, name: pair.element.name, address: pair.element.address,
                    city: pair.element.city, position: pair.offset, note: index == 1 ? "本月想去" : "",
                    image: pair.element.image
                )
            }
            return TasteMapHybridListDTO(
                id: "hybrid-list-\(index)",
                title: ["杭州私藏餐厅", "周末想吃", "年度 TOP 10", "适合约会", "朋友来杭带吃"][index],
                description: index == 2 ? "按我的真实到访评分排序。" : "基于真实记录整理的食单。",
                visibility: index == 4 ? "public" : index == 3 ? "friends" : "private",
                isRanked: index == 2, isOwnedByViewer: true, ownerName: "Lafayette",
                restaurantCount: values.count, restaurants: values,
                updatedAt: generatedAt
            )
        }
        return TasteMapHybridContentSnapshotDTO(
            generatedAt: generatedAt,
            discovery: .init(forYou: discovery, similarTaste: similar, trending: trending),
            community: .init(following: activities.filter { $0.user.isFollowing }, latest: activities),
            lists: lists
        )
    }

    private func replacingImage(
        _ value: TasteMapHybridContentRestaurantDTO,
        with image: TasteMapHybridImageDescriptor
    ) -> TasteMapHybridContentRestaurantDTO {
        TasteMapHybridContentRestaurantDTO(
            id: value.id, name: value.name, address: value.address, city: value.city,
            latitude: value.latitude, longitude: value.longitude, tags: value.tags,
            referencePrice: value.referencePrice, image: image
        )
    }

    private func debugUGCDescriptor(
        value: TasteMapHybridRestaurantDTO,
        ownerID: String,
        kind: TasteMapHybridImageKind
    ) -> TasteMapHybridImageDescriptor {
        guard let resourceURL = value.image.resourceURL, let photoID = value.image.photoID else {
            return debugCategoryDescriptor(name: value.name, tags: value.tags, seed: value.id)
        }
        let visitID: String?
        switch kind {
        case .activityPhoto: visitID = "visual-qa-activity"
        default: visitID = nil
        }
        return TasteMapHybridImageDescriptor(
            kind: kind, resourceURL: resourceURL, photoID: photoID,
            restaurantID: value.id, visitID: visitID, sourceOwnerID: ownerID,
            visibility: "public", exportAllowed: false, attributionRequired: false,
            accessibilityLabel: "\(value.name) 用户实拍"
        )
    }

    private func debugCategoryDescriptor(
        name: String,
        tags: [String],
        seed: String
    ) -> TasteMapHybridImageDescriptor {
#if TASTEMAP_HYBRID_BRIDGE_CORE
        return TasteMapHybridImageDescriptor(
            kind: .foodCategoryVisual, stableSeed: seed, categoryVisualID: "other",
            exportAllowed: false, attributionRequired: false,
            accessibilityLabel: "\(name) 餐饮分类图示"
        )
#else
        return categoryDescriptor(name: name, tags: tags, seed: seed)
#endif
    }

    private func contentRestaurant(_ value: TasteMapHybridRestaurantDTO) -> TasteMapHybridContentRestaurantDTO {
        TasteMapHybridContentRestaurantDTO(
            id: value.id, name: value.name, address: value.address, city: value.city,
            latitude: value.latitude, longitude: value.longitude, tags: value.tags,
            referencePrice: value.referencePrice, image: value.image
        )
    }

#if !TASTEMAP_HYBRID_BRIDGE_CORE
    private func contentRestaurant(_ value: DiscoveryRestaurantProjectionV1) -> TasteMapHybridContentRestaurantDTO {
        TasteMapHybridContentRestaurantDTO(
            id: value.globalKey, name: value.name, address: value.address, city: value.city,
            latitude: value.latitude, longitude: value.longitude, tags: value.tags,
            referencePrice: value.pricePerPerson,
            image: publicUGCOrCategoryDescriptor(photo: value.photo, seed: value.globalKey, name: value.name, tags: value.tags)
        )
    }

    private func discoveryDTO(
        context value: DiscoveryCachedCardContext,
        restaurant: DiscoveryRestaurantProjectionV1
    ) -> TasteMapHybridDiscoveryItemDTO {
        TasteMapHybridDiscoveryItemDTO(
            id: value.id, mode: value.mode.rawValue, restaurant: contentRestaurant(restaurant),
            viewerState: value.viewerState.rawValue,
            sourceUser: value.sourceUser.map(personDTO),
            activityRating: value.activity?.rating,
            activityVisitedAt: value.activity?.visitedAt,
            interaction: value.activity.flatMap { activity in
                value.sourceUser.map { user in
                    .init(
                        activityID: nil, visitID: activity.visitId,
                        authorID: user.userId, restaurantID: restaurant.globalKey
                    )
                }
            },
            likedByViewer: false,
            likeCount: 0,
            commentCount: 0,
            communityRating: .init(
                valueOutOfFive: value.ratings.community.value,
                sampleCount: value.ratings.community.sampleCount
            ),
            reason: value.reasons.first?.text ?? "来自 Taste Map 的真实记录",
            similarityPercent: value.similarity?.percent,
            sharedRestaurantCount: value.similarity?.sharedRestaurantCount,
            uniqueVisitorCount: value.trend?.uniqueVisitorCount,
            wantToGoCount: value.trend?.wantToGoCount,
            rank: value.rank
        )
    }

    private func personDTO(_ value: DiscoveryPublicUserProjectionV1) -> TasteMapHybridPersonDTO {
        .init(
            id: value.userId, name: value.displayName, city: value.city,
            avatarPhotoID: value.avatarPhotoId, avatarPresetID: value.avatarPresetId.rawValue,
            isFollowing: value.isFollowing
        )
    }

    private func personDTO(_ value: PublicContentUserV1) -> TasteMapHybridPersonDTO {
        .init(
            id: value.userId, name: value.displayName, city: value.city,
            avatarPhotoID: value.avatarPhotoId, avatarPresetID: value.avatarPresetId.rawValue,
            isFollowing: value.isFollowing
        )
    }

    private func communityDTO(_ value: PublicContentItemV1) -> TasteMapHybridActivityItemDTO {
        TasteMapHybridActivityItemDTO(
            id: value.id, kind: value.kind.rawValue, eventAt: value.eventAt,
            user: personDTO(value.user), restaurant: contentRestaurant(value.restaurant.discoveryProjection),
            visitID: value.visit?.id,
            interaction: value.visit.map { visit in
                .init(
                    activityID: value.id, visitID: visit.id,
                    authorID: value.user.userId, restaurantID: value.restaurant.globalKey
                )
            },
            visitRating: value.visit?.rating, note: value.visit?.note,
            viewerState: value.viewerState.rawValue, likedByViewer: value.engagement.likedByViewer,
            likeCount: value.engagement.likeCount, commentCount: value.engagement.commentCount
        )
    }

    private func uniqueCommunityItems(_ values: [TasteMapHybridActivityItemDTO]) -> [TasteMapHybridActivityItemDTO] {
        Array(Dictionary(values.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values)
            .sorted { $0.eventAt > $1.eventAt || ($0.eventAt == $1.eventAt && $0.id < $1.id) }
    }

    private func listRestaurantDTO(item: RestaurantListItem) -> TasteMapHybridListRestaurantDTO? {
        guard let value = item.restaurantSnapshot else { return nil }
        return listRestaurantDTO(value: value, position: item.position, note: item.note)
    }

    private func listRestaurantDTO(item: PublicListItemDTO) -> TasteMapHybridListRestaurantDTO {
        listRestaurantDTO(value: item.restaurant, position: item.position, note: item.note)
    }

    private func listRestaurantDTO(
        value: RestaurantListPlaceContractV1,
        position: Int,
        note: String
    ) -> TasteMapHybridListRestaurantDTO {
        .init(
            id: value.restaurantId, name: value.name, address: value.address, city: value.city,
            position: position, note: note,
            image: publicImageDescriptor(photoID: value.markerPhotoId, merchantURL: value.merchantImageUrl, seed: value.globalKey, name: value.name)
        )
    }

    private func publicImageDescriptor(
        photoID: String?, merchantURL: String?, seed: String, name: String
    ) -> TasteMapHybridImageDescriptor {
        if let photoID, !photoID.isEmpty {
            let encoded = photoID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? photoID
            return .init(
                kind: .publicOrCached,
                resourceURL: "tastemap-resource://public-photo/\(encoded)/display",
                photoID: photoID,
                accessibilityLabel: "\(name) 餐厅图片"
            )
        }
        if let merchantURL, let url = URL(string: merchantURL), ["https", "http"].contains(url.scheme?.lowercased()) {
            return .init(kind: .providerMerchant, resourceURL: merchantURL, accessibilityLabel: "\(name) 餐厅图片")
        }
        return .init(kind: .foodDiningFallback, stableSeed: seed, accessibilityLabel: "\(name) 餐饮图示")
    }

    private func publicUGCOrCategoryDescriptor(
        photo: DiscoveryPhotoProjectionV1?, seed: String, name: String, tags: [String]
    ) -> TasteMapHybridImageDescriptor {
        guard let photo, !photo.photoId.isEmpty else {
            return categoryDescriptor(name: name, tags: tags, seed: seed)
        }
        let encoded = photo.photoId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? photo.photoId
        let kind: TasteMapHybridImageKind
        switch photo.sourceType {
        case "currentOwnerPhoto": kind = .ownerPhoto
        case "activityAuthorPhoto": kind = .activityPhoto
        default: kind = .publicUGC
        }
        return .init(
            kind: kind,
            resourceURL: "tastemap-resource://public-photo/\(encoded)/display",
            photoID: photo.photoId,
            restaurantID: photo.restaurantId,
            visitID: photo.visitId,
            sourceOwnerID: photo.ownerUserId,
            visibility: photo.visibility ?? "public",
            exportAllowed: photo.exportAllowed ?? false,
            attributionRequired: false,
            accessibilityLabel: "\(name) 用户实拍"
        )
    }

    private func categoryDescriptor(name: String, tags: [String], seed: String) -> TasteMapHybridImageDescriptor {
        .init(
            kind: .foodCategoryVisual,
            stableSeed: seed,
            categoryVisualID: FoodCategoryVisualResolver.resolve(name: name, tags: tags).rawValue,
            exportAllowed: false,
            attributionRequired: false,
            accessibilityLabel: "\(name) 餐饮分类图示"
        )
    }
#endif

    private func scopedRestaurants() throws -> [TasteMapHybridRestaurantDTO] {
        if let projectedRestaurantSnapshot { return projectedRestaurantSnapshot }
        let restaurants = try context.fetch(FetchDescriptor<Restaurant>()).filter {
            $0.ownerUserID == ownerUserID && $0.deletedAt == nil
        }
        let visits = try context.fetch(FetchDescriptor<Visit>()).filter {
            $0.ownerUserID == ownerUserID && $0.deletedAt == nil
        }
#if !TASTEMAP_HYBRID_BRIDGE_CORE
        let photos = try context.fetch(FetchDescriptor<PhotoAsset>()).filter {
            $0.ownerUserID == ownerUserID && $0.deletedAt == nil && $0.binaryDeletedAt == nil
        }
        let photosByRestaurant = Dictionary(grouping: photos.compactMap { photo in
            photo.restaurantId.map { ($0, photo) }
        }, by: \.0)
#endif
        let visitsByRestaurant = Dictionary(grouping: visits, by: \Visit.restaurantId)
#if DEBUG
        projectedRestaurantSnapshotBuildCount += 1
#endif
        let snapshot = restaurants.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }.map { restaurant in
            let restaurantVisits = (visitsByRestaurant[restaurant.id] ?? []).sorted {
                if $0.visitedAt != $1.visitedAt { return $0.visitedAt > $1.visitedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            let rated = restaurantVisits.compactMap(\.rating)
            let averageRating = rated.isEmpty ? nil : rounded(rated.reduce(0, +) / Double(rated.count), places: 1)
#if TASTEMAP_HYBRID_BRIDGE_CORE
            // The standalone Bridge package intentionally excludes the App's
            // full photo/storage contracts. Its deterministic fixture injects
            // equivalent safe metadata; the shipping App follows the canonical
            // RestaurantImagePriorityPolicy path below.
            let persistedMetadata = TasteMapHybridRestaurantMetadata()
#else
            let contract = restaurant.remoteRecordData.flatMap {
                try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0)
            }
            let preferredPhoto = RestaurantImagePhotoSelectionPolicy.preferredPhoto(
                restaurantID: restaurant.id,
                photos: (photosByRestaurant[restaurant.id] ?? []).map(\.1),
                referencedPhotoID: contract?.markerPhotoId
            )
            let persistedMetadata = TasteMapHybridRestaurantMetadata(
                tags: contract?.tags ?? [],
                phone: contract?.phone,
                openingHours: contract?.openingHours,
                referencePrice: contract?.pricePerPerson,
                localUserPhotoID: preferredPhoto?.id,
                publicOrCachedPhotoID: contract?.markerPhotoId,
                providerMerchantImageURL: contract?.merchantImageUrl,
                localUserPhotoVisitID: preferredPhoto?.visitId.map { $0.uuidString.lowercased() },
                localUserPhotoVisibility: preferredPhoto?.visibility.rawValue
            )
#endif
            let metadata = metadataByRestaurantID[restaurant.id] ?? persistedMetadata
            let referencePrice = metadata.referencePrice ?? median(restaurantVisits.compactMap(decimalDouble))
            return TasteMapHybridRestaurantDTO(
                id: restaurant.remoteID ?? restaurant.id.uuidString.lowercased(),
                name: restaurant.name,
                address: restaurant.address,
                city: restaurant.city,
                latitude: restaurant.latitude,
                longitude: restaurant.longitude,
                status: restaurant.status.rawValue,
                tags: metadata.tags,
                phone: metadata.phone,
                openingHours: metadata.openingHours,
                referencePrice: referencePrice,
                visitCount: restaurantVisits.count,
                averageRating: averageRating,
                scoreOutOfTen: averageRating.map { rounded($0 * 2, places: 1) },
                latestVisitDate: restaurantVisits.first.map { Self.dateFormatter.string(from: $0.visitedAt) },
                createdAt: Self.dateFormatter.string(from: restaurant.createdAt),
                updatedAt: Self.dateFormatter.string(from: restaurant.updatedAt),
                visits: restaurantVisits.map(visitDTO),
                image: imageDescriptor(restaurant: restaurant, metadata: metadata)
            )
        }
        projectedRestaurantSnapshot = snapshot
        return snapshot
    }

    private func visitDTO(_ visit: Visit) -> TasteMapHybridVisitDTO {
#if TASTEMAP_HYBRID_BRIDGE_CORE
        return TasteMapHybridVisitDTO(
            id: visit.remoteID ?? visit.id.uuidString.lowercased(),
            restaurantId: visit.restaurantId.uuidString.lowercased(),
            visitedAt: Self.dateFormatter.string(from: visit.visitedAt),
            rating: visit.rating,
            valueRating: visit.valueRating,
            environmentRating: visit.environmentRating,
            serviceRating: visit.serviceRating,
            myActualSpend: visit.myActualSpend.map { NSDecimalNumber(decimal: $0).doubleValue },
            totalPrice: visit.totalPrice.map { NSDecimalNumber(decimal: $0).doubleValue },
            pricePerPerson: visit.pricePerPerson.map { NSDecimalNumber(decimal: $0).doubleValue },
            diningMode: visit.diningMode.rawValue,
            visibility: visit.visibility.rawValue,
            paymentMode: visit.paymentModeRawValue,
            queueDuration: visit.queueDurationRawValue,
            diningOccasions: visit.diningOccasionRawValues,
            diningOccasionText: visit.diningOccasionText ?? "",
            valueTags: visit.valueTags,
            environmentTags: visit.environmentTags,
            serviceTags: visit.serviceTags,
            noiseLevel: visit.noiseLevelRawValue,
            diningDuration: visit.diningDurationRawValue,
            portionLevel: visit.portionLevelRawValue,
            transportConvenience: visit.transportConvenienceRawValue,
            specialNotes: visit.specialNotes ?? "",
            companions: visit.companionNames,
            companionIds: visit.companionIDs,
            recommendationSourceType: visit.recommendationSourceTypeRawValue,
            recommendationSourceUserId: visit.recommendationSourceUserID,
            recommendationSourceText: visit.recommendationSourceText ?? "",
            sharedMealId: visit.sharedMealID,
            partySize: visit.partySize,
            note: visit.note ?? "",
            dishes: [],
            photos: [],
            createdAt: Self.dateFormatter.string(from: visit.createdAt),
            updatedAt: Self.dateFormatter.string(from: visit.updatedAt)
        )
#else
        let allDishes = ((try? context.fetch(FetchDescriptor<Dish>())) ?? []).filter {
            $0.ownerUserID == ownerUserID && $0.deletedAt == nil
        }
        let associations = ((try? context.fetch(FetchDescriptor<VisitDish>())) ?? []).filter {
            $0.ownerUserID == ownerUserID && $0.visitId == visit.id && $0.deletedAt == nil
        }.sorted { $0.sortOrder < $1.sortOrder }
        let associatedIDs = Set(associations.map(\.dishId))
        let dishes = allDishes.filter { associatedIDs.contains($0.id) || (associations.isEmpty && $0.visitId == visit.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
        let photos = ((try? context.fetch(FetchDescriptor<PhotoAsset>())) ?? []).filter {
            $0.ownerUserID == ownerUserID && $0.visitId == visit.id && $0.deletedAt == nil
                && $0.binaryDeletedAt == nil
        }.sorted { $0.sortOrder < $1.sortOrder }
        return TasteMapHybridVisitDTO(
            id: visit.remoteID ?? visit.id.uuidString.lowercased(),
            restaurantId: visit.restaurantId.uuidString.lowercased(),
            visitedAt: Self.dateFormatter.string(from: visit.visitedAt),
            rating: visit.rating,
            valueRating: visit.valueRating,
            environmentRating: visit.environmentRating,
            serviceRating: visit.serviceRating,
            myActualSpend: visit.myActualSpend.map { NSDecimalNumber(decimal: $0).doubleValue },
            totalPrice: visit.totalPrice.map { NSDecimalNumber(decimal: $0).doubleValue },
            pricePerPerson: visit.pricePerPerson.map { NSDecimalNumber(decimal: $0).doubleValue },
            diningMode: visit.diningMode.rawValue,
            visibility: visit.visibility.rawValue,
            paymentMode: visit.paymentModeRawValue,
            queueDuration: visit.queueDurationRawValue,
            diningOccasions: visit.diningOccasionRawValues,
            diningOccasionText: visit.diningOccasionText ?? "",
            valueTags: visit.valueTags,
            environmentTags: visit.environmentTags,
            serviceTags: visit.serviceTags,
            noiseLevel: visit.noiseLevelRawValue,
            diningDuration: visit.diningDurationRawValue,
            portionLevel: visit.portionLevelRawValue,
            transportConvenience: visit.transportConvenienceRawValue,
            specialNotes: visit.specialNotes ?? "",
            companions: visit.companionNames,
            companionIds: visit.companionIDs,
            recommendationSourceType: visit.recommendationSourceTypeRawValue,
            recommendationSourceUserId: visit.recommendationSourceUserID,
            recommendationSourceText: visit.recommendationSourceText ?? "",
            sharedMealId: visit.sharedMealID,
            partySize: visit.partySize,
            note: visit.note ?? "",
            dishes: dishes.map { dish in
                TasteMapHybridVisitDishDTO(
                    id: dish.remoteID ?? dish.id.uuidString.lowercased(),
                    name: dish.name,
                    taste: dish.taste,
                    rating: dish.rating,
                    price: dish.price.map { NSDecimalNumber(decimal: $0).doubleValue },
                    photoID: photos.first(where: { $0.dishId == dish.id }).map {
                        $0.remoteID ?? $0.id.uuidString.lowercased()
                    }
                )
            },
            photos: photos.map(photoDescriptor),
            createdAt: Self.dateFormatter.string(from: visit.createdAt),
            updatedAt: Self.dateFormatter.string(from: visit.updatedAt)
        )
#endif
    }

#if !TASTEMAP_HYBRID_BRIDGE_CORE
    private func photoDescriptor(_ photo: PhotoAsset) -> TasteMapHybridImageDescriptor {
        let id = photo.remoteID ?? photo.id.uuidString.lowercased()
        return TasteMapHybridImageDescriptor(
            kind: .nativeResource,
            resourceURL: "tastemap-resource://photo/\(id)/thumbnail",
            photoID: id,
            accessibilityLabel: "用户实拍"
        )
    }
#endif

    private func imageDescriptor(
        restaurant: Restaurant,
        metadata: TasteMapHybridRestaurantMetadata
    ) -> TasteMapHybridImageDescriptor {
        let resolution = RestaurantImagePriorityPolicy.resolution(
            localUserPhotoID: metadata.localUserPhotoID,
            publicOrCachedPhotoID: metadata.publicOrCachedPhotoID,
            providerMerchantImageURL: metadata.providerMerchantImageURL
        )
        let label = "\(restaurant.name) 餐厅图片"
        switch resolution.preferredSource {
        case .localUserPhoto(let id):
            return TasteMapHybridImageDescriptor(
                kind: .ownerPhoto,
                resourceURL: "tastemap-resource://photo/\(id.uuidString.lowercased())/display",
                photoID: id.uuidString.lowercased(),
                restaurantID: restaurant.remoteID ?? restaurant.id.uuidString.lowercased(),
                visitID: metadata.localUserPhotoVisitID,
                sourceOwnerID: ownerUserID,
                visibility: metadata.localUserPhotoVisibility ?? "private",
                exportAllowed: true,
                attributionRequired: false,
                accessibilityLabel: label
            )
        case .publicOrCachedPhoto(let id):
            let segmentCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            let encoded = id.addingPercentEncoding(withAllowedCharacters: segmentCharacters) ?? id
            return TasteMapHybridImageDescriptor(
                kind: .publicUGC,
                resourceURL: "tastemap-resource://public-photo/\(encoded)/display",
                photoID: id,
                restaurantID: restaurant.remoteID ?? restaurant.id.uuidString.lowercased(),
                sourceOwnerID: ownerUserID,
                visibility: "public",
                exportAllowed: false,
                attributionRequired: false,
                accessibilityLabel: label
            )
        case .providerMerchantImage, .foodDiningFallback:
            return debugCategoryDescriptor(
                name: restaurant.name,
                tags: metadata.tags,
                seed: restaurant.id.uuidString.lowercased()
            )
        }
    }

    private func decimalDouble(_ visit: Visit) -> Double? {
        visit.pricePerPerson.map { NSDecimalNumber(decimal: $0).doubleValue }
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private func rounded(_ value: Double, places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (value * scale).rounded() / scale
    }

    private func stableValues(_ values: [String]) -> [String] {
        Array(Set(values.compactMap(nonempty))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func nonempty(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == false ? normalized : nil
    }

    private static func contains(_ item: TasteMapHybridRestaurantDTO, in bounds: TasteMapHybridMapBounds) -> Bool {
        let longitudeMatches = bounds.west <= bounds.east
            ? item.longitude >= bounds.west && item.longitude <= bounds.east
            : item.longitude >= bounds.west || item.longitude <= bounds.east
        return item.latitude >= bounds.south && item.latitude <= bounds.north && longitudeMatches
    }

    private static func squaredDistance(
        _ item: TasteMapHybridRestaurantDTO,
        from origin: TasteMapHybridMapCoordinate
    ) -> Double {
        pow(item.latitude - origin.latitude, 2) + pow(item.longitude - origin.longitude, 2)
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

#if !TASTEMAP_HYBRID_BRIDGE_CORE
/// Resolves only Restaurant projections already visible to the authenticated
/// owner through Discovery, Community, or Restaurant Lists. It is deliberately
/// not a general identifier lookup and never exposes another user's private
/// Restaurant/Visit rows.
@MainActor
struct TasteMapHybridResolvedRestaurantReference: Sendable {
    let projection: DiscoveryRestaurantProjectionV1
    let viewerState: DiscoveryViewerRestaurantStateV1
    let updatedAt: Date
}

@MainActor
enum TasteMapHybridRestaurantReferenceResolver {
    @discardableResult
    static func cacheCandidate(
        _ candidate: RestaurantCandidate,
        ownerUserID: String,
        context: ModelContext,
        now: Date = .now
    ) throws -> String {
        let identities = candidate.placeIdentities.map {
            DiscoveryPlaceIdentityV1(
                provider: $0.provider,
                externalId: $0.externalID,
                isPrimary: $0.isPrimary
            )
        }
        let primary = identities.first(where: \.isPrimary) ?? identities.first
        let globalKey = primary.map { "\($0.provider.rawValue):\($0.externalId)" }
            ?? "candidate:\(candidate.id.uuidString.lowercased())"
        let projection = DiscoveryRestaurantProjectionV1(
            globalKey: globalKey,
            placeIdentities: identities,
            name: candidate.name,
            address: candidate.address,
            city: candidate.city,
            latitude: candidate.latitude,
            longitude: candidate.longitude,
            tags: [],
            pricePerPerson: nil,
            merchantImageUrl: candidate.photoURL?.absoluteString,
            markerEmoji: "",
            photo: nil
        )
        let cacheID = "\(ownerUserID)|\(globalKey)"
        let cached = try context.fetch(FetchDescriptor<CachedDiscoveryRestaurant>())
        if let existing = cached.first(where: { $0.cacheID == cacheID }) {
            existing.projectionData = try JSONEncoder().encode(projection)
            existing.fetchedAt = now
        } else {
            context.insert(try CachedDiscoveryRestaurant(
                currentUserID: ownerUserID,
                projection: projection,
                fetchedAt: now
            ))
        }
        try context.save()
        return globalKey
    }

    static func resolve(
        identifier: String,
        ownerUserID: String,
        context: ModelContext
    ) throws -> TasteMapHybridResolvedRestaurantReference? {
        let key = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }

        let discoveryRestaurants = try context.fetch(FetchDescriptor<CachedDiscoveryRestaurant>())
            .filter { $0.currentUserID == ownerUserID }
        if let cached = discoveryRestaurants.first(where: {
            $0.globalKey.caseInsensitiveCompare(key) == .orderedSame
        }), let projection = cached.projection {
            let placements = try context.fetch(FetchDescriptor<CachedDiscoveryPlacement>()).filter {
                $0.currentUserID == ownerUserID && $0.globalKey == cached.globalKey
            }
            return .init(
                projection: projection,
                viewerState: strongestViewerState(placements.compactMap { $0.context?.viewerState }),
                updatedAt: max(cached.fetchedAt, placements.map(\.generatedAt).max() ?? cached.fetchedAt)
            )
        }

        let community = try context.fetch(FetchDescriptor<CachedCommunityContent>())
            .filter { $0.currentUserID == ownerUserID }
        let communityMatches = community.compactMap { cached -> (CachedCommunityContent, PublicContentItemV1)? in
            guard let item = cached.item,
                  item.restaurant.globalKey.caseInsensitiveCompare(key) == .orderedSame else { return nil }
            return (cached, item)
        }
        if let first = communityMatches.first {
            return .init(
                projection: first.1.restaurant.discoveryProjection,
                viewerState: strongestViewerState(communityMatches.map { $0.1.viewerState }),
                updatedAt: communityMatches.map { $0.0.fetchedAt }.max() ?? first.0.fetchedAt
            )
        }

        let ownedListItems = try context.fetch(FetchDescriptor<RestaurantListItem>()).filter {
            $0.ownerUserID == ownerUserID && $0.deletedAt == nil
        }
        if let item = ownedListItems.first(where: { item in
            item.restaurantGlobalKey.caseInsensitiveCompare(key) == .orderedSame
                || item.restaurantReferenceID.caseInsensitiveCompare(key) == .orderedSame
                || item.restaurantSnapshot?.restaurantId.caseInsensitiveCompare(key) == .orderedSame
        }), let place = item.restaurantSnapshot {
            return .init(projection: place.discoveryProjection, viewerState: .none, updatedAt: item.updatedAt)
        }

        let publicListItems = try context.fetch(FetchDescriptor<CachedPublicRestaurantListItem>())
            .filter { $0.viewerUserID == ownerUserID }
        if let cached = publicListItems.first(where: { cached in
            guard let item = cached.item else { return false }
            return item.restaurant.globalKey.caseInsensitiveCompare(key) == .orderedSame
                || item.restaurant.restaurantId.caseInsensitiveCompare(key) == .orderedSame
        }), let item = cached.item {
            return .init(
                projection: item.restaurant.discoveryProjection,
                viewerState: .none,
                updatedAt: cached.fetchedAt
            )
        }
        return nil
    }

    private static func strongestViewerState(
        _ values: [DiscoveryViewerRestaurantStateV1]
    ) -> DiscoveryViewerRestaurantStateV1 {
        if values.contains(.visited) { return .visited }
        if values.contains(.wantToGo) { return .wantToGo }
        return .none
    }
}
#endif
