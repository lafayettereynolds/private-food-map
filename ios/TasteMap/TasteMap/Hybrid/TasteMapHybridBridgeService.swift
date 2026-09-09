import Foundation
import SwiftData

public struct TasteMapHybridRestaurantMetadata: Sendable {
    public let tags: [String]
    public let phone: String?
    public let websiteUrl: String?
    public let openingHours: String?
    public let referencePrice: Double?
    public let localUserPhotoID: UUID?
    public let publicOrCachedPhotoID: String?
    public let providerMerchantImageURL: String?
    public let localUserPhotoVisitID: String?
    public let localUserPhotoVisibility: String?
    public let markerType: String
    public let markerEmoji: String

    public init(
        tags: [String] = [],
        phone: String? = nil,
        websiteUrl: String? = nil,
        openingHours: String? = nil,
        referencePrice: Double? = nil,
        localUserPhotoID: UUID? = nil,
        publicOrCachedPhotoID: String? = nil,
        providerMerchantImageURL: String? = nil,
        localUserPhotoVisitID: String? = nil,
        localUserPhotoVisibility: String? = nil,
        markerType: String = "emoji",
        markerEmoji: String = "🍽️"
    ) {
        self.tags = tags
        self.phone = phone
        self.websiteUrl = websiteUrl
        self.openingHours = openingHours
        self.referencePrice = referencePrice
        self.localUserPhotoID = localUserPhotoID
        self.publicOrCachedPhotoID = publicOrCachedPhotoID
        self.providerMerchantImageURL = providerMerchantImageURL
        self.localUserPhotoVisitID = localUserPhotoVisitID
        self.localUserPhotoVisibility = localUserPhotoVisibility
        self.markerType = markerType
        self.markerEmoji = markerEmoji
    }
}

public enum TasteMapHybridServiceError: Error, Sendable {
    case authRequired
    case profileMissing
    case restaurantMissing
    case invalidRequest
}

#if !TASTEMAP_HYBRID_BRIDGE_CORE
private struct TasteMapHybridVisitProjectionResources {
    let dishesByID: [UUID: Dish]
    let dishesByVisitID: [UUID: [Dish]]
    let associationsByVisitID: [UUID: [VisitDish]]
    let photosByVisitID: [UUID: [PhotoAsset]]
    let photosByRestaurantID: [UUID: [PhotoAsset]]
}
#endif

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
    /// Supplied by the owner's asynchronous refresh coordinator. Optional for
    /// bridge-v1 compatibility and offline/legacy consumers.
    public var discoveryRefreshStatus: [String: TasteMapHybridDiscoveryRefreshStatusDTO]?
    public var discoveryEvidenceAvailability: [String: TasteMapDiscoveryEvidenceAvailabilityDTO]?
#if !TASTEMAP_HYBRID_BRIDGE_CORE
    var sessionRestaurantReference: ((String) -> TasteMapHybridResolvedRestaurantReference?)?
    var didDeleteRestaurantWithVisit: ((Set<String>, Set<String>) -> Void)?
#endif

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
    /// The exact versioned For You projection most recently returned by
    /// content.snapshot. Map consumes this cache instead of ranking again.
    private var cachedForYouRecommendationSnapshot: (
        generatedAt: String,
        items: [TasteMapHybridDiscoveryItemDTO]
    )?
#if !TASTEMAP_HYBRID_BRIDGE_CORE
    private var visitProjectionResources: TasteMapHybridVisitProjectionResources?
#endif
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
        var follows = try context.fetch(FetchDescriptor<CachedFollow>()).filter {
            $0.currentUserID == ownerUserID && $0.deletedAt == nil
        }
#if !TASTEMAP_HYBRID_BRIDGE_CORE
        // Repair legacy caches written before Following-feed authors were
        // mirrored into LocalSocialStore. Only the contradictory zero state is
        // migrated; a populated authoritative Follow cache stays untouched.
        if !follows.contains(where: { $0.followerUserID == ownerUserID }) {
            let authors = try context.fetch(FetchDescriptor<CachedCommunityContent>())
                .filter {
                    $0.currentUserID == ownerUserID
                        && $0.routeKey == LocalCommunityStore.feedRoute(.following)
                }
                .compactMap(\.item?.user)
            if !authors.isEmpty {
                try LocalSocialStore(context: context).cacheFollowingFeedAuthors(
                    authors,
                    currentUserID: ownerUserID
                )
                follows = try context.fetch(FetchDescriptor<CachedFollow>()).filter {
                    $0.currentUserID == ownerUserID && $0.deletedAt == nil
                }
            }
        }
#endif
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
            followingCount: follows.filter { $0.followerUserID == ownerUserID }.count,
            analyticsIdentity: try analyticsIdentity(restaurants: restaurants)
        )
    }

    private func analyticsIdentity(restaurants: [TasteMapHybridRestaurantDTO]) throws -> TasteMapHybridAnalyticsIdentityDTO? {
#if TASTEMAP_HYBRID_BRIDGE_CORE
        // The lean Package target does not contain private P2-F directories.
        return nil
#else
        let snapshot = ModelContext(context.container)
        let companions = try snapshot.fetch(FetchDescriptor<DiningCompanion>()).filter { $0.ownerUserId == ownerUserID }
        let sources = try snapshot.fetch(FetchDescriptor<RecommendationSource>()).filter { $0.ownerUserId == ownerUserID }
        let visitIDs = Set(restaurants.flatMap(\.visits).map(\.id))
        let visits = try snapshot.fetch(FetchDescriptor<Visit>()).filter {
            $0.ownerUserID == ownerUserID && $0.deletedAt == nil
                && visitIDs.contains($0.remoteID ?? $0.id.uuidString.lowercased())
        }
        return TasteMapHybridAnalyticsIdentityDTO(
            ownerUserID: ownerUserID, recordOwnerID: ownerUserID,
            companions: companions.map { item in
                TasteMapHybridAnalyticsDirectoryEntryDTO(
                    id: item.id.uuidString.lowercased(), ownerUserID: ownerUserID,
                    displayName: item.displayName,
                    identifiers: Array(Set([item.id.uuidString.lowercased(), item.remoteID].compactMap { $0 })).sorted(),
                    updatedAt: Self.dateFormatter.string(from: item.updatedAt),
                    deletedAt: item.deletedAt.map { Self.dateFormatter.string(from: $0) }
                )
            }.sorted { $0.id < $1.id },
            sources: sources.map { item in
                TasteMapHybridAnalyticsDirectoryEntryDTO(
                    id: item.id.uuidString.lowercased(), ownerUserID: ownerUserID,
                    displayName: item.displayName,
                    identifiers: Array(Set([item.id.uuidString.lowercased(), item.remoteID].compactMap { $0 })).sorted(),
                    updatedAt: Self.dateFormatter.string(from: item.updatedAt),
                    deletedAt: item.deletedAt.map { Self.dateFormatter.string(from: $0) },
                    sourceType: item.sourceType.rawValue
                )
            }.sorted { $0.id < $1.id },
            visitSourceLinks: visits.map { item in
                TasteMapHybridAnalyticsVisitSourceLinkDTO(
                    visitID: item.remoteID ?? item.id.uuidString.lowercased(), sourceID: item.recommendationSourceID
                )
            }.sorted { $0.visitID < $1.visitID }
        )
#endif
    }

    public func restaurantDetail(id: String) throws -> TasteMapHybridRestaurantDetailDTO {
        // Reads are not invalidation boundaries. Reuse an already projected
        // owner snapshot so opening a Detail does not rescan every Visit, Dish
        // and Photo, while retaining the selected-only path for a cold deep link.
        if let cached = projectedRestaurantSnapshot?.first(where: {
            $0.id.caseInsensitiveCompare(id) == .orderedSame
        }) {
            return try ownedDetail(cached)
        }
        if let restaurant = try ownedRestaurantIfPresent(identifier: id) {
            return try ownedDetail(try ownedRestaurantDTO(restaurant))
        }
#if !TASTEMAP_HYBRID_BRIDGE_CORE
        if let reference = try sessionRestaurantReference?(id) ?? TasteMapHybridRestaurantReferenceResolver.resolve(
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
                return try ownedDetail(try ownedRestaurantDTO(local))
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
        var contentRestaurant = restaurant
#if !TASTEMAP_HYBRID_BRIDGE_CORE
        if let local = try context.fetch(FetchDescriptor<Restaurant>()).first(where: {
            $0.ownerUserID == ownerUserID && $0.deletedAt == nil
                && ($0.remoteID?.caseInsensitiveCompare(restaurant.id) == .orderedSame
                    || $0.id.uuidString.caseInsensitiveCompare(restaurant.id) == .orderedSame)
        }) {
            let keys = RestaurantDetailMetadata(restaurant: local).globalIdentityKeys.sorted()
            var sources = restaurant.contentImageResolution?.sources ?? []
            for key in keys {
                let reference = try sessionRestaurantReference?(key)
                    ?? TasteMapHybridRestaurantReferenceResolver.resolve(identifier: key, ownerUserID: ownerUserID, context: context)
                guard let projection = reference?.projection, projection.photo?.isActualDiningPhoto == true else { continue }
                let descriptor = publicUGCOrCategoryDescriptor(photo: projection.photo, seed: projection.globalKey,
                                                               name: restaurant.name, tags: restaurant.tags)
                if !sources.contains(where: { $0.photoID == descriptor.photoID }) { sources.append(descriptor) }
            }
            let fallback = categoryDescriptor(name: restaurant.name, tags: restaurant.tags, seed: restaurant.id)
            contentRestaurant.contentImageResolution = .init(sources: sources, fallback: fallback)
            contentRestaurant.contentImage = sources.first ?? fallback
        }
#endif
        return TasteMapHybridRestaurantDetailDTO(
            restaurant: contentRestaurant,
            socialStats: try socialStats(for: restaurant),
            viewerState: restaurant.status == "visited" ? "visited" : "want_to_go",
            editableVisitIDs: restaurant.visits.map(\.id),
            capabilities: .owned,
            deletablePhotoIDs: try deletablePhotoIDs(for: restaurant.id)
        )
    }

    private func deletablePhotoIDs(for restaurantID: String) throws -> [String] {
#if TASTEMAP_HYBRID_BRIDGE_CORE
        return []
#else
        guard let local = try context.fetch(FetchDescriptor<Restaurant>()).first(where: {
            $0.ownerUserID == ownerUserID && $0.deletedAt == nil &&
                ($0.id.uuidString.caseInsensitiveCompare(restaurantID) == .orderedSame ||
                 $0.remoteID?.caseInsensitiveCompare(restaurantID) == .orderedSame)
        }) else { return [] }
        return try context.fetch(FetchDescriptor<PhotoAsset>()).filter {
            $0.ownerUserID == ownerUserID && $0.restaurantId == local.id && $0.deletedAt == nil
        }.flatMap { [$0.id.uuidString.lowercased(), $0.remoteID].compactMap { $0 } }
#endif
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
            tags: RestaurantCandidate.categoryLabels(value.tags),
            phone: value.phone,
            websiteUrl: value.websiteUrl,
            openingHours: value.openingHours,
            referencePrice: value.pricePerPerson,
            visitCount: 0,
            averageRating: nil,
            scoreOutOfTen: nil,
            latestVisitDate: nil,
            createdAt: timestamp,
            updatedAt: timestamp,
            visits: [],
            image: publicUGCOrCategoryDescriptor(photo: value.photo, seed: value.globalKey, name: value.name, tags: value.tags),
            markerType: "emoji",
            markerEmoji: value.markerEmoji,
            contentImage: publicUGCOrCategoryDescriptor(photo: value.photo, seed: value.globalKey, name: value.name, tags: value.tags)
        )
        return TasteMapHybridRestaurantDetailDTO(
            restaurant: restaurant,
            socialStats: try reference.socialStats ?? socialStats(globalIdentityKeys: [value.globalKey]),
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
        if membershipTier != "member" && (nonempty(request.filters.companion) != nil || nonempty(request.filters.recommendationSource) != nil || nonempty(request.filters.recommendationSourceType) != nil) {
            throw TasteMapHybridBridgeErrorDTO(code: "premium_filters_required", message: "推荐来源和饭搭子筛选需要 Premium。", recoverable: true, details: nil)
        }
        guard request.requestID.count >= 8, request.requestID.count <= 128 else {
            throw TasteMapHybridServiceError.invalidRequest
        }
        let all = try scopedRestaurants()
        let normalizedSearch = request.search.trimmingCharacters(in: .whitespacesAndNewlines).folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        let visitCutoff: Date? = request.filters.visitPeriod.flatMap { period in
            let months = period == "sixMonths" ? 6 : period == "year" ? 12 : 0
            return months > 0 ? Calendar.current.date(byAdding: .month, value: -months, to: .now) : nil
        }
        let selectedOccasions = Set(request.filters.diningOccasions ?? [])
        let hasVisitScopedFilters = nonempty(request.filters.diningMode) != nil
            || nonempty(request.filters.queueDuration) != nil
            || !selectedOccasions.isEmpty
            || nonempty(request.filters.recommendationSourceType) != nil
            || nonempty(request.filters.recommendationSource) != nil
            || nonempty(request.filters.priceRange) != nil
            || request.filters.visitPeriod != nil
            || nonempty(request.filters.companion) != nil
        func visitMatches(_ visit: TasteMapHybridVisitDTO) -> Bool {
            if let diningMode = nonempty(request.filters.diningMode), visit.diningMode != diningMode { return false }
            if let queue = nonempty(request.filters.queueDuration) {
                if queue == "unrecorded" {
                    if visit.queueDuration != nil { return false }
                } else if visit.queueDuration != queue { return false }
            }
            if !selectedOccasions.isEmpty,
               selectedOccasions.isDisjoint(with: visit.diningOccasions) { return false }
            if let sourceType = nonempty(request.filters.recommendationSourceType),
               visit.recommendationSourceType != sourceType { return false }
            if let source = nonempty(request.filters.recommendationSource),
               visit.recommendationSourceText != source { return false }
            if let companion = nonempty(request.filters.companion),
               !visit.companions.contains(companion) { return false }
            if let priceRange = nonempty(request.filters.priceRange),
               !Self.price(visit.pricePerPerson, matches: priceRange) { return false }
            if let visitCutoff {
                guard let visitedAt = Self.dateFormatter.date(from: visit.visitedAt),
                      visitedAt >= visitCutoff else { return false }
            }
            return true
        }
        // This direct bridge route remains available for compatibility, but
        // it must project the same For You snapshot as Discovery. The Hybrid
        // Map UI normally receives that snapshot directly and does not issue
        // a second recommendation query at all.
        if cachedForYouRecommendationSnapshot == nil { _ = try contentSnapshot() }
        let recommendationSnapshot = cachedForYouRecommendationSnapshot
            ?? (generatedAt: Self.dateFormatter.string(from: .now), items: [])
        let recommendationSource = recommendationSnapshot.items.map {
            recommendationMapRestaurant($0, generatedAt: recommendationSnapshot.generatedAt)
        }
        // Cities come from the selected scope before applying city, search or
        // viewport filters. Recommendations must never inherit personal cities.
        let citySource = request.scope == .recommended ? recommendationSource : all.filter {
            $0.status == (request.scope == .wantToGo ? "wantToGo" : "visited")
        }
        let options = TasteMapHybridMapBrowseOptions(
            cities: RestaurantCityFilterIdentity.options(citySource.map(\.city)),
            companions: stableValues(all.flatMap { $0.visits.flatMap(\.companions) }),
            cuisines: stableValues(all.flatMap(\.tags)),
            recommendationSources: stableValues(all.flatMap { $0.visits.map(\.recommendationSourceText) })
        )
        func filteredValues(
            for scope: TasteMapHybridMapScope,
            includeBounds: Bool
        ) -> [TasteMapHybridRestaurantDTO] {
            let source = scope == .recommended ? recommendationSource : all
            let desiredStatus = scope == .wantToGo ? "wantToGo" : "visited"
            return source.filter { item in
                if scope != .recommended, item.status != desiredStatus { return false }
                if includeBounds, let bounds = request.bounds, !Self.contains(item, in: bounds) { return false }
                if let city = nonempty(request.filters.city), !RestaurantCityFilterIdentity.matches(item.city, city) { return false }
                if let score = request.filters.minimumScoreOutOfTen, (item.scoreOutOfTen ?? -1) < score { return false }
                if let scoreBands = request.filters.scoreBands, !scoreBands.isEmpty {
                    guard let band = Self.scoreBand(item.scoreOutOfTen), scoreBands.contains(band) else { return false }
                }
                if let spend = request.filters.maximumSpend, (item.referencePrice ?? .greatestFiniteMagnitude) > spend { return false }
                if let cuisine = nonempty(request.filters.cuisine), !item.tags.contains(cuisine) { return false }
                if let kilometers = request.filters.distanceKilometers {
                    guard let origin = request.currentLocation,
                          Self.distanceMeters(item, from: origin) <= Double(kilometers) * 1_000 else { return false }
                }
                if scope == .visited {
                    if let visits = request.filters.minimumVisitCount, item.visitCount < visits { return false }
                    if hasVisitScopedFilters, !item.visits.contains(where: visitMatches) { return false }
                }
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
            return source.filter { scope == .recommended || $0.status == desiredStatus }.count
        }
        let scopeCounts = TasteMapHybridMapScopeCounts(
            visited: scopeTotal(.visited),
            wantToGo: scopeTotal(.wantToGo),
            recommended: scopeTotal(.recommended)
        )
        var values = filteredValues(for: request.scope, includeBounds: true)
        if request.scope != .recommended || request.sort == .rating || request.sort == .distance {
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
#if DEBUG
        if ownerUserID == "tm_hybrid_debug" {
            return cacheContentSnapshot(debugContentSnapshot(restaurants: restaurants, generatedAt: generatedAt))
        }
#endif
#if !TASTEMAP_HYBRID_BRIDGE_CORE && DEBUG
        // Visual QA is an isolated Debug-only session. It intentionally uses
        // deterministic owner-scoped records instead of remote social APIs so
        // Lafayette can inspect rich content without a real Apple credential.
        if TasteMapUITestFixtures.usesVisualQA {
            return cacheContentSnapshot(debugContentSnapshot(restaurants: restaurants, generatedAt: generatedAt))
        }
#endif
#if TASTEMAP_HYBRID_BRIDGE_CORE
        return cacheContentSnapshot(TasteMapHybridContentSnapshotDTO(
            generatedAt: generatedAt,
            discovery: .init(forYou: [], similarTaste: [], trending: []),
            community: .init(following: [], latest: []),
            lists: []
        ))
#else
        // Refresh writes use isolated transactions. Read their committed values
        // without reusing registered Discovery objects from this long-lived
        // service context; owner/editor and map projections remain untouched.
        let discoveryReadContext = ModelContext(context.container)
        discoveryReadContext.autosaveEnabled = false
        let discoveryRestaurants = Dictionary(uniqueKeysWithValues:
            try discoveryReadContext.fetch(FetchDescriptor<CachedDiscoveryRestaurant>())
                .filter { $0.currentUserID == ownerUserID }
                .compactMap { cached in cached.projection.map { (cached.globalKey, $0) } }
        )
        let discoveryItems = try discoveryReadContext.fetch(FetchDescriptor<CachedDiscoveryPlacement>())
            .filter { $0.currentUserID == ownerUserID }
            .compactMap { placement -> TasteMapHybridDiscoveryItemDTO? in
                if let status = discoveryRefreshStatus?[placement.modeValue] {
                    guard status.state != .restricted, status.state != .unavailable,
                          placement.city == status.city, placement.trendWindowDays == status.windowDays else { return nil }
                }
                guard let projection = discoveryRestaurants[placement.globalKey],
                      let value = placement.context else { return nil }
                return discoveryDTO(context: value, restaurant: projection)
            }
            .reduce(into: [String: TasteMapHybridDiscoveryItemDTO]()) { result, item in
                if result[item.id] == nil || (result[item.id]?.rank ?? .max) > item.rank { result[item.id] = item }
            }
            .values
            .sorted { $0.rank < $1.rank || ($0.rank == $1.rank && $0.id < $1.id) }
            .filter(isEligibleForDiscovery)

        let cachedCommunity = try context.fetch(FetchDescriptor<CachedCommunityContent>())
            .filter { $0.currentUserID == ownerUserID }
        let latest = uniqueCommunityItems(
            cachedCommunity.compactMap { $0.item }
                .filter(\.isEligibleForDiscoveryFeed)
                .map(communityDTO)
        )
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
        let liveRestaurantsByReferenceID = restaurants.reduce(into: [String: TasteMapHybridRestaurantDTO]()) { result, restaurant in
            result[restaurant.id] = restaurant
        }
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
                restaurants: items.compactMap { item in
                    listRestaurantDTO(
                        item: item,
                        liveRestaurant: liveRestaurantsByReferenceID[item.restaurantReferenceID]
                            ?? item.localRestaurantID.flatMap { liveRestaurantsByReferenceID[$0.uuidString.lowercased()] }
                    )
                },
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
        return cacheContentSnapshot(TasteMapHybridContentSnapshotDTO(
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
        ))
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
            guard let reference = try sessionRestaurantReference?(request.restaurantID) ?? TasteMapHybridRestaurantReferenceResolver.resolve(
                identifier: request.restaurantID,
                ownerUserID: ownerUserID,
                context: context
            ) else { throw TasteMapHybridServiceError.restaurantMissing }
            restaurant = nil
            candidate = reference.projection.restaurantCandidate
            existingVisit = nil
        }
        let retainedPhotos = try context.fetch(FetchDescriptor<PhotoAsset>()).filter {
            $0.ownerUserID == ownerUserID && $0.deletedAt == nil
                && existingVisit != nil && $0.visitId == existingVisit?.id
        }
        let retainedPhotoIDs = Set(retainedPhotos.flatMap { photo in
            [photo.id.uuidString.lowercased(), photo.remoteID?.lowercased()].compactMap { $0 }
        })
        let newPhotoIDs = Set((request.draft.pendingPhotos ?? []).map { $0.photoID.lowercased() })
            .subtracting(retainedPhotoIDs)
        if membershipTier != "member" {
            let retainedDishPhotoIDs = Set(retainedPhotos.filter { $0.dishId != nil }.flatMap {
                [$0.id.uuidString.lowercased(), $0.remoteID?.lowercased()].compactMap { $0 }
            })
            if request.draft.dishes.contains(where: { $0.photoID.map { !retainedDishPhotoIDs.contains($0.lowercased()) } ?? false }) {
                throw TasteMapHybridBridgeErrorDTO(code: "dish_photos_requires_premium", message: "菜品照片仅限 Premium；已有照片会继续保留。", recoverable: true, details: nil)
            }
        }
        guard PremiumFeatureAccessPolicy.permitsVisitPhotoAddition(
            existingCount: retainedPhotos.count, newCount: newPhotoIDs.count,
            membershipStatus: membershipTier == "member" ? .premium : .free
        ) else {
            let limit = PremiumFeatureAccessPolicy.visitPhotoLimit(membershipStatus: membershipTier == "member" ? .premium : .free)
            throw TasteMapHybridBridgeErrorDTO(
                code: "visit_photo_limit", message: "每次到访最多可添加 \(limit) 张照片；已有照片会继续保留。",
                recoverable: true, details: nil
            )
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
#if !TASTEMAP_HYBRID_BRIDGE_CORE
        visitProjectionResources = nil
#endif
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
        // Capture identifiers before an unsynced graph can be physically removed.
        let restaurantID = restaurant.remoteID ?? restaurant.id.uuidString.lowercased()
        let visitID = visit.remoteID ?? visit.id.uuidString.lowercased()
        let record = try SyncRecordMapper.restaurantRecord(restaurant)
        let restaurantAliases = Set(([restaurantID, restaurant.id.uuidString] + record.placeIdentities.map {
            "\($0.provider.rawValue):\($0.externalId)"
        }).map { $0.lowercased() })
        let visitAliases = Set([visitID.lowercased(), visit.id.uuidString.lowercased()])
        let deletedRestaurantID = try LocalTasteMapStore(context: context).delete(visit, actorUserID: ownerUserID)
        projectedRestaurantSnapshot = nil
        visitProjectionResources = nil
        if deletedRestaurantID != nil { didDeleteRestaurantWithVisit?(restaurantAliases, visitAliases) }
        return TasteMapHybridVisitMutationResultDTO(
            restaurantID: restaurantID,
            visitID: visitID,
            updatedAt: Self.dateFormatter.string(from: .now),
            deletedRestaurantID: deletedRestaurantID == nil ? nil : restaurantID
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

#if TASTEMAP_HYBRID_BRIDGE_CORE
    private func ownedRestaurantIfPresent(identifier: String) throws -> Restaurant? {
        try context.fetch(FetchDescriptor<Restaurant>()).first(where: {
            $0.ownerUserID == ownerUserID && $0.deletedAt == nil
                && ($0.remoteID?.caseInsensitiveCompare(identifier) == .orderedSame
                    || $0.id.uuidString.caseInsensitiveCompare(identifier) == .orderedSame)
        })
    }
#endif

    private func debugContentSnapshot(
        restaurants: [TasteMapHybridRestaurantDTO],
        generatedAt: String
    ) -> TasteMapHybridContentSnapshotDTO {
        let names = ["林夏", "周舟", "陈一碗", "江南胃", "阿岚", "西湖小柚", "陆小满", "一只饭团"]
        let similarTasteRatings = [4.5, 4.0, 5.0, 4.5, 4.0, 4.5, 5.0, 4.0]
        func person(_ index: Int, city: String) -> TasteMapHybridPersonDTO {
            TasteMapHybridPersonDTO(
                id: "tm_demo_\(index)", name: names[index % names.count], city: city,
                avatarPhotoID: nil, avatarPresetID: ["otter", "polar-bear", "fox", "capybara"][index % 4],
                isFollowing: index.isMultiple(of: 2)
            )
        }
        // The isolated QA producer exercises the same evidence anatomy as the
        // server. Additional personal reasons use actual fixture Visit data,
        // never arbitrary card-index counts or another account's history.
        func historyReasons(for candidate: TasteMapHybridContentRestaurantDTO) -> [TasteMapHybridDiscoveryReasonDTO] {
            let normalizedTags = Set(candidate.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
            let related = restaurants.filter { restaurant in
                restaurant.id != candidate.id && restaurant.visitCount > 0
                    && restaurant.averageRating.map { $0.isFinite && $0 > 0 && $0 <= 5 } == true
                    && restaurant.tags.contains { normalizedTags.contains($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
            }
            guard !related.isEmpty else { return [] }
            let labels = candidate.tags.filter { tag in related.contains { restaurant in
                restaurant.tags.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            } }.prefix(2).joined(separator: "、")
            let mean = related.compactMap(\.averageRating).reduce(0, +) / Double(related.count) * 2
            var reasons = [TasteMapHybridDiscoveryReasonDTO(code: "HIGH_CUISINE_MATCH", text: "你过去 \(related.count) 家\(labels)相关餐厅的平均评分为 \(String(format: "%.1f", mean))/10")]
            let repeated = related.filter { $0.visitCount >= 2 }.count
            if repeated > 0 {
                reasons.append(.init(code: "REPEAT_VISIT_PATTERN", text: "\(labels)是你会重复到访的类型，\(repeated) 家同类餐厅曾再次到访"))
            }
            return reasons
        }
        let discovery = Array(restaurants.prefix(12).enumerated()).map { index, value in
            let fixtureRating = index == 3 ? nil : max(3.5, 4.5 - Double(index) * 0.1)
            let activityRating = value.averageRating ?? fixtureRating
            let communityRating = activityRating.map { max(0, $0 - 0.05) }
            let ratingSampleCount = communityRating == nil ? 0 : max(10, value.visitCount)
            let original = contentRestaurant(value)
            let content = index == 0 ? original : replacingImage(
                original,
                with: index.isMultiple(of: 2)
                    ? debugCategoryDescriptor(name: value.name, tags: RestaurantCandidate.categoryLabels(value.tags), seed: value.id)
                    : debugUGCDescriptor(value: value, ownerID: person(index, city: value.city).id, kind: .publicUGC)
            )
            let referenceName = restaurants[(index + 1) % restaurants.count].name
            let reason = "与你去过的「\(referenceName)」相似 \(88 - index)%"
            return TasteMapHybridDiscoveryItemDTO(
                id: "hybrid-discovery-\(index)", mode: "for_you", restaurant: content,
                viewerState: index == 0 ? "none" : index == 1 ? "want_to_go" : value.status == "visited" ? "visited" : "want_to_go", sourceUser: nil,
                activityRating: nil, activityVisitedAt: nil,
                interaction: nil,
                likedByViewer: index == 1, likeCount: 12 + index * 5, commentCount: 2 + index,
                communityRating: .init(valueOutOfFive: communityRating, sampleCount: ratingSampleCount),
                personalTastePercent: 88 - index,
                reasons: Array(([.init(code: "TASTE_TAG_MATCH", text: reason)] + historyReasons(for: content)).prefix(3)), reason: reason,
                similarityPercent: nil, sharedRestaurantCount: nil, trendWindowDays: nil,
                uniqueVisitorCount: nil, wantToGoCount: nil,
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
                activityImages: debugActivityImages(restaurant: item.restaurant, authorID: user.id, visitID: "demo-visit-similar-\(index)", index: index),
                viewerState: item.viewerState, sourceUser: user,
                activityRating: similarTasteRatings[index % similarTasteRatings.count],
                activityVisitedAt: restaurants[index].latestVisitDate ?? generatedAt,
                interaction: .init(
                    activityID: "similar-activity-\(index)", visitID: "demo-visit-similar-\(index)",
                    authorID: user.id, restaurantID: item.restaurant.id
                ), likedByViewer: item.likedByViewer,
                likeCount: item.likeCount, commentCount: item.commentCount,
                communityRating: item.communityRating,
                personalTastePercent: nil,
                reasons: [.init(
                    code: "SIMILAR_USERS",
                    text: "基于 \(6 + index) 家共同评分餐厅，你与这位用户的口味相似度为 \(82 - index * 3)%"
                ), .init(
                    code: "SOURCE_VISIT_RATING",
                    text: "这位同味用户在本次到访给这家餐厅 \(String(format: "%g", similarTasteRatings[index % similarTasteRatings.count] * 2))/10 分"
                )] + Array(historyReasons(for: item.restaurant).prefix(1)),
                reason: "基于 \(6 + index) 家共同评分餐厅，你与这位用户的口味相似度为 \(82 - index * 3)%",
                similarityPercent: 82 - index * 3, sharedRestaurantCount: 6 + index,
                trendWindowDays: nil, uniqueVisitorCount: nil, wantToGoCount: nil, rank: item.rank
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
                interaction: nil, likedByViewer: item.likedByViewer,
                likeCount: item.likeCount, commentCount: item.commentCount,
                communityRating: item.communityRating,
                personalTastePercent: nil,
                reasons: [
                    .init(code: "TRENDING_UNIQUE_USERS", text: "近 7 天有 \(18 + index * 4) 位用户到访"),
                    .init(code: "RECENT_WANT_TO_GO", text: "近期有 \(9 + index) 位用户加入想吃")
                ],
                reason: "近 7 天有 \(18 + index * 4) 位用户到访",
                similarityPercent: nil, sharedRestaurantCount: nil,
                trendWindowDays: 7, uniqueVisitorCount: 18 + index * 4,
                wantToGoCount: 9 + index, rank: item.rank
            )
        }
        let activityVisitRatings: [Double?] = [4.5, 4, 4.8, 4.3, nil, 4.6, 4.5, 4.7, 3.9, nil, 4.4, nil]
        let activities = discovery.enumerated().map { index, item in
            let user = person(index, city: item.restaurant.city)
            let visual = index.isMultiple(of: 2)
                ? debugUGCDescriptor(value: restaurants[index], ownerID: user.id, kind: .activityPhoto)
                : debugCategoryDescriptor(name: item.restaurant.name, tags: item.restaurant.tags, seed: item.restaurant.id)
            return TasteMapHybridActivityItemDTO(
                id: "hybrid-activity-\(index)", kind: index % 5 == 4 ? "want_to_go" : "visit",
                eventAt: restaurants[index].latestVisitDate ?? generatedAt,
                user: user, restaurant: replacingImage(item.restaurant, with: visual),
                activityImages: index % 5 == 4 ? nil
                    : debugActivityImages(restaurant: item.restaurant, authorID: user.id, visitID: "demo-visit-\(index)", index: index == 6 ? 4 : index),
                visitID: index % 5 == 4 ? nil : "demo-visit-\(index)",
                interaction: index % 5 == 4 ? nil : .init(
                    activityID: "hybrid-activity-\(index)", visitID: "demo-visit-\(index)",
                    authorID: user.id, restaurantID: item.restaurant.id
                ),
                visitRating: index % 5 == 4 ? nil : activityVisitRatings[index],
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
            community: .init(
                following: activities.filter(isEligibleForDiscovery).filter { $0.user.isFollowing },
                latest: activities.filter(isEligibleForDiscovery)
            ),
            lists: lists
        )
    }

    private func replacingImage(
        _ value: TasteMapHybridContentRestaurantDTO,
        with image: TasteMapHybridImageDescriptor
    ) -> TasteMapHybridContentRestaurantDTO {
        TasteMapHybridContentRestaurantDTO(
            id: value.id, name: value.name, address: value.address, city: value.city,
            latitude: value.latitude, longitude: value.longitude, tags: RestaurantCandidate.categoryLabels(value.tags),
            referencePrice: value.referencePrice, image: image
        )
    }

    private func debugActivityImages(
        restaurant: TasteMapHybridContentRestaurantDTO, authorID: String, visitID: String, index: Int
    ) -> [TasteMapHybridImageDescriptor]? {
#if DEBUG
        var resources = ["chinese.png", "japanese.png", "hotpot-grill.png", "western.png", "cafe.png", "mixed.png"]
            .map { "/food-heroes/\($0)" }
        let pattern = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"320\" height=\"320\"><rect width=\"320\" height=\"320\" fill=\"#d9e9e6\"/><text x=\"160\" y=\"165\" text-anchor=\"middle\" font-size=\"36\" fill=\"#244c43\">QA PHOTO 7</text></svg>"
        resources.append("data:image/svg+xml;base64," + Data(pattern.utf8).base64EncodedString())
        let counts = [1, 2, 4, 5, 6, 7, 0, 3]
        return resources.prefix(index < counts.count ? counts[index] : 0).enumerated().map { slot, resourceURL in
            .init(kind: .activityPhoto, resourceURL: resourceURL, photoID: "debug-album-\(visitID)-\(slot)",
                  restaurantID: restaurant.id, visitID: visitID, sourceOwnerID: authorID,
                  visibility: "public", exportAllowed: false, attributionRequired: false,
                  accessibilityLabel: "\(restaurant.name) 隔离布局测试图 \(slot + 1)")
        }
#else
        return nil
#endif
    }

    private func debugUGCDescriptor(
        value: TasteMapHybridRestaurantDTO,
        ownerID: String,
        kind: TasteMapHybridImageKind
    ) -> TasteMapHybridImageDescriptor {
        guard let resourceURL = value.contentImage?.resourceURL, let photoID = value.contentImage?.photoID else {
            return debugCategoryDescriptor(name: value.name, tags: RestaurantCandidate.categoryLabels(value.tags), seed: value.id)
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
        return categoryDescriptor(name: name, tags: tags, seed: seed)
    }

    private func contentRestaurant(_ value: TasteMapHybridRestaurantDTO) -> TasteMapHybridContentRestaurantDTO {
        TasteMapHybridContentRestaurantDTO(
            id: value.id, name: value.name, address: value.address, city: value.city,
            latitude: value.latitude, longitude: value.longitude, tags: RestaurantCandidate.categoryLabels(value.tags),
            referencePrice: value.referencePrice,
            image: value.contentImage ?? categoryDescriptor(name: value.name, tags: RestaurantCandidate.categoryLabels(value.tags), seed: value.id),
            contentImageResolution: value.contentImageResolution
        )
    }

    private func recommendationMapRestaurant(
        _ item: TasteMapHybridDiscoveryItemDTO,
        generatedAt: String
    ) -> TasteMapHybridRestaurantDTO {
        let value = item.restaurant
        let publicRating = item.communityRating.valueOutOfFive
        return TasteMapHybridRestaurantDTO(
            id: value.id,
            name: value.name,
            address: value.address,
            city: value.city,
            latitude: value.latitude,
            longitude: value.longitude,
            status: item.viewerState == "visited" ? "visited" : "wantToGo",
            tags: RestaurantCandidate.categoryLabels(value.tags),
            phone: nil,
            openingHours: nil,
            referencePrice: value.referencePrice,
            visitCount: 0,
            averageRating: publicRating,
            scoreOutOfTen: publicRating.map { rounded($0 * 2, places: 1) },
            latestVisitDate: nil,
            createdAt: generatedAt,
            updatedAt: generatedAt,
            visits: [],
            image: value.image,
            markerType: nil,
            markerEmoji: nil
        )
    }

#if !TASTEMAP_HYBRID_BRIDGE_CORE
    private func contentRestaurant(_ value: DiscoveryRestaurantProjectionV1) -> TasteMapHybridContentRestaurantDTO {
        TasteMapHybridContentRestaurantDTO(
            id: value.globalKey, name: value.name, address: value.address, city: value.city,
            latitude: value.latitude, longitude: value.longitude, tags: RestaurantCandidate.categoryLabels(value.tags),
            referencePrice: value.pricePerPerson,
            image: publicUGCOrCategoryDescriptor(photo: value.photo, seed: value.globalKey, name: value.name, tags: value.tags)
        )
    }

    /// Read-only projection for the independent authenticated page channel.
    /// No page placement, social count, rank or persistent cache is synthesized.
    func discoveryPageSource(_ page: DiscoveryPageV1) throws -> TasteMapDiscoveryPageSource {
        guard let mode = TasteMapHybridDiscoveryMode(rawValue: page.mode.rawValue),
              page.items.allSatisfy({ $0.mode == page.mode }) else { throw SyncAPIError.invalidResponse }
        return .init(mode: mode, city: page.city, generatedAt: page.generatedAt,
                     items: page.items.map { discoveryDTO(context: DiscoveryCachedCardContext(card: $0), restaurant: $0.restaurant) },
                     nextCursor: page.nextCursor, evidenceAvailability: page.evidenceAvailability,
                     appliedQuery: page.appliedQuery, filterCapabilities: page.filterCapabilities, filterTaxonomy: page.filterTaxonomy)
    }

    func discoveryCitySource(_ page: DiscoveryPageV1) throws -> TasteMapDiscoveryCitySource {
        let projected = try discoveryPageSource(page)
        let items = projected.items.filter(isEligibleForDiscovery)
        let acceptedIDs = Set(items.map(\.id))
        var references: [String: TasteMapHybridResolvedRestaurantReference] = [:]
        for card in page.items where acceptedIDs.contains(card.id) {
            let ratings = card.ratings
            references[card.restaurant.globalKey.lowercased()] = .init(
                projection: card.restaurant, viewerState: card.viewerState, updatedAt: .now,
                socialStats: .init(overallUserRating: ratings.community.value.map { $0 * 2 }, overallUserCount: ratings.community.sampleCount,
                                   friendAverageRating: ratings.friends.value.map { $0 * 2 }, friendUserCount: ratings.friends.sampleCount,
                                   similarTasteAverageRating: ratings.similarTaste.value.map { $0 * 2 }, similarTasteUserCount: ratings.similarTaste.sampleCount,
                                   repeatVisitRate: nil, repeatVisitorCount: 0, uniqueVisitorCount: ratings.community.sampleCount))
        }
        return .init(city: page.city, generatedAt: page.generatedAt, discoveryItems: items,
                     nextCursor: page.nextCursor, references: references, evidenceAvailability: page.evidenceAvailability,
                     appliedQuery: page.appliedQuery, filterCapabilities: page.filterCapabilities, filterTaxonomy: page.filterTaxonomy)
    }

    func communityCitySource(_ page: CommunityFeedPageV1) throws -> TasteMapDiscoveryCitySource {
        guard let city = page.city else { throw SyncAPIError.invalidResponse }
        let values = page.items.filter(\.isEligibleForDiscoveryFeed)
        var references: [String: TasteMapHybridResolvedRestaurantReference] = [:]
        for item in values {
            references[item.restaurant.globalKey.lowercased()] = .init(
                projection: item.restaurant.discoveryProjection, viewerState: item.viewerState, updatedAt: .now)
        }
        return .init(city: city, generatedAt: page.generatedAt, activityItems: values.map(communityDTO),
                     nextCursor: page.nextCursor, references: references, engagementKnown: true,
                     appliedQuery: page.appliedQuery, filterCapabilities: page.filterCapabilities, filterTaxonomy: page.filterTaxonomy)
    }

#if DEBUG
    /// Independent complete QA dataset, not the canonical first-page cache.
    /// The response is visibly labelled by the shared UI; no network is enabled.
    func debugCitySource(mode: String, city: String, cursor: String?, windowDays: Int,
                         query requestedQuery: TasteMapDiscoveryAppliedQuery? = nil, limit: Int = 20) throws -> TasteMapDiscoveryCitySource {
        let query = try requestedQuery ?? TasteMapDiscoveryAppliedQuery.normalized(mode: mode, filters: nil, sort: nil, preferences: nil)
        guard query.preferences == .init(), query.filters.priceRange == nil, (1...40).contains(limit) else {
            throw DiscoveryQueryValidation.unsupported()
        }
        let cities: [(String, Double, Double)] = [("杭州", 30.2741, 120.1551), ("上海", 31.2304, 121.4737),
                                                ("北京", 39.9042, 116.4074), ("纽约", 40.7143, -74.0060)]
        let selected = cities.first { RestaurantCityFilterIdentity.matches($0.0, city) }
        let filters = query.filters
        func distance(_ index: Int) -> Double {
            guard let selected, let reference = filters.distance?.reference else { return 0 }
            let radians = Double.pi / 180
            let latitude = selected.1 + Double(index) * 0.0001
            let a = pow(sin((latitude - reference.latitude) * radians / 2), 2)
                + cos(latitude * radians) * cos(reference.latitude * radians)
                * pow(sin((selected.2 - reference.longitude) * radians / 2), 2)
            return 6_371_000 * 2 * asin(sqrt(min(1, max(0, a))))
        }
        // Evaluate the entire fixture before pagination. All 36 sample records
        // truthfully have 中餐, viewer none, 8 reviewers/8.5 and no actual photo.
        let indices = (selected == nil ? [] : Array(0..<36)).filter { index in
            (filters.cuisines.isEmpty || filters.cuisines.contains("中餐"))
                && filters.types.isEmpty
                && (filters.viewerStates.isEmpty || filters.viewerStates.contains("none"))
                && !filters.requireActualPhoto
                && (filters.minimumPublicScoreOutOfTen ?? 0) <= 8.5
                && (filters.minimumPublicRatingUsers ?? 0) <= 8
                // This older isolated fixture has match=88 but no historical
                // predicted-rating producer. Missing predictions never pass a bound.
                && filters.minimumPredictedLikingOutOfTen == nil
                && (filters.minimumTasteMatchPercent.map { mode == "for_you" && $0 <= 88 } ?? true)
                && (filters.distance.map { distance(index) <= $0.maximumMeters } ?? true)
        }.sorted { left, right in
            // All other supported scores/timestamps already tie or follow index
            // order in this fixture; never invent preference or public ratings.
            if query.sort == "distance", distance(left) != distance(right) { return distance(left) < distance(right) }
            return left < right
        }
        let cursorPrefix = "qa-city-\(RestaurantCityFilterIdentity.key(city))-\(mode)-\(windowDays)-\(limit)-\(Data(query.fingerprint.utf8).base64EncodedString())-"
        let start: Int
        if let cursor {
            guard cursor.hasPrefix(cursorPrefix), let offset = Int(cursor.dropFirst(cursorPrefix.count)),
                  offset > 0, offset < indices.count, offset.isMultiple(of: limit) else { throw SyncAPIError.invalidResponse }
            start = offset
        } else { start = 0 }
        let end = min(start + limit, indices.count)
        var source = TasteMapDiscoveryCitySource(city: city, generatedAt: "2026-09-06T00:00:00Z",
            nextCursor: end < indices.count ? cursorPrefix + String(end) : nil, engagementKnown: true, dataSource: "debug_city_fixture",
            appliedQuery: query,
            filterCapabilities: .init(cuisines: true, types: true, publicScore: true, publicRatingUsers: true,
                viewerStates: true, actualPhoto: true, distanceReferenceSources: ["device_location", "user_selected_point"]),
            filterTaxonomy: .init(cuisines: TasteMapDiscoveryFilters.cuisineTaxonomy, types: TasteMapDiscoveryFilters.typeTaxonomy))
        guard let selected, start < end else { return source }
        for index in indices[start..<end] {
            let id = "qa-city:\(selected.0):\(index)"
            let activityID = "qa-city-activity:\(selected.0):\(index)"
            let visitID = "demo-visit-city-\(selected.0)-\(index)"
            let authorID = "tm_qa_city_author_\(index % 4)"
            let projection = DiscoveryRestaurantProjectionV1(globalKey: id, placeIdentities: [],
                name: "\(selected.0)模拟餐厅 \(index + 1)", address: "模拟数据 · 城市测试街 \(index + 1) 号", city: selected.0,
                latitude: selected.1 + Double(index) * 0.0001, longitude: selected.2,
                tags: ["中餐"], pricePerPerson: Double(40 + index), merchantImageUrl: nil, markerEmoji: "", photo: nil)
            let restaurant = contentRestaurant(projection)
            let person = TasteMapHybridPersonDTO(id: authorID, name: "模拟食客 \(index % 4 + 1)", city: selected.0,
                avatarPhotoID: nil, avatarPresetID: "otter", isFollowing: mode == "following")
            let visitedAt = String(format: "2026-09-%02dT12:00:00Z", max(1, 6 - index / 6))
            let interaction = TasteMapHybridActivityInteractionDTO(activityID: ["following", "latest"].contains(mode) ? activityID : nil,
                visitID: visitID, authorID: authorID, restaurantID: id)
            source.references[id.lowercased()] = .init(projection: projection, viewerState: .none, updatedAt: .now)
            if ["following", "latest"].contains(mode) {
                source.activityItems.append(.init(id: activityID, kind: "visit", eventAt: visitedAt, user: person,
                    restaurant: restaurant, visitID: visitID, interaction: interaction, visitRating: 4.25,
                    note: "模拟数据：用于验收城市切换、分页和返回，不代表真实餐厅或评价。", viewerState: "none",
                    likedByViewer: false, likeCount: 12 + index * 5, commentCount: 2 + index))
            } else {
                source.discoveryItems.append(.init(id: "qa-city-\(mode)-\(selected.0)-\(index)", mode: mode, restaurant: restaurant,
                    viewerState: "none", sourceUser: mode == "similar_taste" ? person : nil,
                    activityRating: mode == "similar_taste" ? 4.25 : nil, activityVisitedAt: mode == "similar_taste" ? visitedAt : nil,
                    interaction: mode == "similar_taste" ? interaction : nil,
                    likedByViewer: false, likeCount: 12 + index * 5, commentCount: 2 + index,
                    communityRating: .init(valueOutOfFive: 4.25, sampleCount: 8), personalTastePercent: mode == "for_you" ? 88 : nil,
                    reasons: [.init(code: "qa_city_fixture", text: "模拟数据 · 独立城市验收样本")], reason: "模拟数据 · 独立城市验收样本",
                    similarityPercent: mode == "similar_taste" ? 86 : nil, sharedRestaurantCount: mode == "similar_taste" ? 8 : nil,
                    trendWindowDays: mode == "trending" ? windowDays : nil, uniqueVisitorCount: mode == "trending" ? 8 : nil,
                    wantToGoCount: mode == "trending" ? 3 : nil, rank: index + 1))
            }
        }
        return source
    }
#endif

    private func discoveryDTO(
        context value: DiscoveryCachedCardContext,
        restaurant: DiscoveryRestaurantProjectionV1
    ) -> TasteMapHybridDiscoveryItemDTO {
        TasteMapHybridDiscoveryItemDTO(
            id: value.id, mode: value.mode.rawValue, restaurant: contentRestaurant(restaurant),
            activityImages: value.mode == .similarTaste ? value.activity.flatMap { activity in
                value.sourceUser.flatMap { user in
                    activityImageDescriptors(photos: activity.photos, visitID: activity.visitId,
                                             authorID: user.userId, visibility: value.cacheScope.rawValue,
                                             restaurant: restaurant)
                }
            } : nil,
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
            personalTastePercent: value.personalTastePercent,
            predictedLiking: value.predictedLiking,
            calibratedLikeProbability: value.calibratedLikeProbability,
            reasons: value.reasons.map { .init(code: $0.code, text: $0.text, evidence: $0.evidence) },
            reason: value.reasons.first?.text ?? "来自 Taste Map 的真实记录",
            similarityPercent: value.similarity?.percent,
            sharedRestaurantCount: value.similarity?.sharedRestaurantCount,
            trendWindowDays: value.trend?.windowDays,
            uniqueVisitorCount: value.trend?.uniqueVisitorCount,
            wantToGoCount: value.trend?.wantToGoCount,
            rank: value.rank,
            tasteEvidence: value.tasteEvidence
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
            activityImages: value.kind == .visit ? value.visit.flatMap { visit in
                guard visit.ownerUserId == value.user.userId else { return nil }
                return activityImageDescriptors(photos: visit.photos.map(\.discoveryProjection), visitID: visit.id,
                                                authorID: visit.ownerUserId, visibility: visit.visibility.rawValue,
                                                restaurant: value.restaurant.discoveryProjection)
            } : nil,
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

    private func listRestaurantDTO(
        item: RestaurantListItem,
        liveRestaurant: TasteMapHybridRestaurantDTO?
    ) -> TasteMapHybridListRestaurantDTO? {
        if let liveRestaurant {
            return TasteMapHybridListRestaurantDTO(
                id: liveRestaurant.id,
                name: liveRestaurant.name,
                address: liveRestaurant.address,
                city: liveRestaurant.city,
                position: item.position,
                note: item.note,
                image: liveRestaurant.image,
                coordinate: Self.listCoordinate(latitude: liveRestaurant.latitude, longitude: liveRestaurant.longitude),
                rating: Self.listViewerRating(liveRestaurant)
            )
        }
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
            image: publicImageDescriptor(photoID: value.markerPhotoId, merchantURL: value.merchantImageUrl, seed: value.globalKey, name: value.name),
            coordinate: Self.listCoordinate(latitude: value.latitude, longitude: value.longitude)
        )
    }

    /// List reads are independent of Discovery refreshes. No public author's
    /// private Restaurant/Visit rows participate in this projection.
    func ownedList(identifier: String) throws -> TasteMapHybridListDTO? {
        guard let list = try context.fetch(FetchDescriptor<RestaurantList>()).first(where: {
            $0.ownerUserID == ownerUserID && $0.deletedAt == nil
                && ($0.remoteID?.caseInsensitiveCompare(identifier) == .orderedSame
                    || $0.id.uuidString.caseInsensitiveCompare(identifier) == .orderedSame)
        }) else { return nil }
        let items = try context.fetch(FetchDescriptor<RestaurantListItem>()).filter {
            $0.ownerUserID == ownerUserID && $0.listID == list.id && $0.deletedAt == nil
        }.sorted { $0.position < $1.position }
        let restaurants = try scopedRestaurants()
        let profile = try context.fetch(FetchDescriptor<UserProfile>()).first {
            $0.tasteMapUserID == ownerUserID && $0.deletedAt == nil
        }
        return .init(
            id: list.remoteID ?? list.id.uuidString.lowercased(), title: list.title,
            description: list.listDescription, visibility: list.visibility.rawValue,
            isRanked: list.isRanked, isOwnedByViewer: true, ownerName: profile?.displayName ?? "我",
            restaurantCount: items.count,
            restaurants: items.compactMap { item in
                listRestaurantDTO(item: item, liveRestaurant: restaurants.first {
                    $0.id.caseInsensitiveCompare(item.restaurantReferenceID) == .orderedSame
                        || item.localRestaurantID?.uuidString.caseInsensitiveCompare($0.id) == .orderedSame
                })
            }, updatedAt: Self.dateFormatter.string(from: list.updatedAt)
        )
    }

    func publicListProjection(_ page: PublicListDetailDTO) throws -> TasteMapHybridListDTO {
        let viewerRestaurants = try scopedRestaurants()
        return .init(
            id: page.list.id, title: page.list.title, description: page.list.description,
            visibility: page.list.visibility.rawValue, isRanked: page.list.isRanked,
            isOwnedByViewer: page.list.owner.userId == ownerUserID,
            ownerName: page.list.owner.displayName, restaurantCount: page.list.restaurantCount,
            restaurants: page.items.map { item in
                var value = listRestaurantDTO(item: item)
                if let owned = viewerRestaurants.first(where: {
                    $0.id.caseInsensitiveCompare(value.id) == .orderedSame
                }) { value.rating = Self.listViewerRating(owned) }
                // The public List API supplies no public rating aggregate.
                // Keep nil; never substitute the author's private Visit score.
                return value
            }, updatedAt: page.list.updatedAt
        )
    }

    private static func listCoordinate(latitude: Double, longitude: Double) -> TasteMapHybridMapCoordinate? {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }

    private static func listViewerRating(_ value: TasteMapHybridRestaurantDTO) -> TasteMapHybridListRatingDTO? {
        .init(valueOutOfTen: value.scoreOutOfTen, source: .viewer,
              sampleCount: value.visits.filter { $0.rating.map { $0.isFinite && $0 > 0 && $0 <= 5 } ?? false }.count)
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
        guard let photo, photo.isActualDiningPhoto, !photo.photoId.isEmpty else {
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

    private func activityImageDescriptors(
        photos: [DiscoveryPhotoProjectionV1]?, visitID: String, authorID: String,
        visibility: String, restaurant: DiscoveryRestaurantProjectionV1
    ) -> [TasteMapHybridImageDescriptor]? {
        DiscoveryPhotoProjectionV1.activityAlbum(photos, visitID: visitID, authorID: authorID)?.map { photo in
            let encoded = photo.photoId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? photo.photoId
            return .init(
                kind: .activityPhoto, resourceURL: "tastemap-resource://public-photo/\(encoded)/display",
                photoID: photo.photoId, restaurantID: photo.restaurantId,
                visitID: photo.visitId ?? visitID, sourceOwnerID: photo.ownerUserId ?? authorID,
                visibility: photo.visibility ?? visibility,
                exportAllowed: authorID == ownerUserID && photo.exportAllowed == true,
                attributionRequired: false, accessibilityLabel: "\(restaurant.name) 到访照片"
            )
        }
    }

#endif

    private func categoryDescriptor(
        name: String,
        tags: [String],
        seed: String,
        preferredEmoji: String? = nil
    ) -> TasteMapHybridImageDescriptor {
        .init(
            kind: .foodCategoryVisual,
            stableSeed: seed,
            categoryVisualID: FoodCategoryVisualResolver.resolve(name: name, tags: tags).rawValue,
            preferredEmoji: preferredEmoji,
            exportAllowed: false,
            attributionRequired: false,
            accessibilityLabel: "\(name) 餐饮分类图示"
        )
    }

    private func cacheContentSnapshot(
        _ snapshot: TasteMapHybridContentSnapshotDTO
    ) -> TasteMapHybridContentSnapshotDTO {
        var seen = Set<String>()
        let canonicalForYou = snapshot.discovery.forYou
            .filter(isEligibleForDiscovery)
            .sorted { $0.rank < $1.rank || ($0.rank == $1.rank && $0.id < $1.id) }
            .filter { item in
                seen.insert(item.restaurant.id.lowercased()).inserted
            }
        let canonical = TasteMapHybridContentSnapshotDTO(
            generatedAt: snapshot.generatedAt,
            discovery: .init(
                forYou: canonicalForYou,
                similarTaste: snapshot.discovery.similarTaste,
                trending: snapshot.discovery.trending,
                refreshStatus: discoveryRefreshStatus ?? snapshot.discovery.refreshStatus,
                evidenceAvailability: discoveryEvidenceAvailability ?? snapshot.discovery.evidenceAvailability
            ),
            community: snapshot.community,
            lists: snapshot.lists
        )
        cachedForYouRecommendationSnapshot = (
            generatedAt: canonical.generatedAt,
            items: canonical.discovery.forYou
        )
        return canonical
    }

    private func isEligibleForDiscovery(_ value: TasteMapHybridActivityItemDTO) -> Bool {
        value.kind != "visit" || (value.visitID != nil && (value.visitRating ?? -1) >= 3.75)
    }

    private func isEligibleForDiscovery(_ value: TasteMapHybridDiscoveryItemDTO) -> Bool {
        if value.mode == "trending" { return true }
        if value.mode == "similar_taste" { return (value.activityRating ?? -1) >= 3.75 }
        let isConcreteUserActivity = value.interaction != nil || value.sourceUser != nil || value.activityVisitedAt != nil
        return !isConcreteUserActivity || (value.activityRating ?? -1) >= 3.75
    }

    private func scopedRestaurants() throws -> [TasteMapHybridRestaurantDTO] {
        if let projectedRestaurantSnapshot { return projectedRestaurantSnapshot }
#if !TASTEMAP_HYBRID_BRIDGE_CORE
        // Only the shipping App owns persistence/sync repair. The isolated
        // Package below applies the same shared status/identity projection.
        _ = try LocalTasteMapStore(context: context).reconcileVisitedRestaurantStatuses(
            actorUserID: ownerUserID
        )
#endif
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
        let statusPartition = RestaurantVisitStatePolicy.partition(
            restaurants: restaurants,
            visits: visits
        )
        let visitedRestaurantIDs = Set(statusPartition.visited.map(\.id))
        let visibleRestaurantIDs = visitedRestaurantIDs.union(statusPartition.wantToGo.map(\.id))
#if DEBUG
        projectedRestaurantSnapshotBuildCount += 1
#endif
        let snapshot = restaurants.filter { visibleRestaurantIDs.contains($0.id) }.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }.map { restaurant in
            let restaurantVisits = (visitsByRestaurant[restaurant.id] ?? []).sorted {
                if $0.visitedAt != $1.visitedAt { return $0.visitedAt > $1.visitedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
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
            let preferredPhoto = contract?.markerType == .image
                ? RestaurantImagePhotoSelectionPolicy.preferredPhoto(
                    restaurantID: restaurant.id,
                    photos: (photosByRestaurant[restaurant.id] ?? []).map(\.1),
                    referencedPhotoID: contract?.markerPhotoId
                )
                : nil
            let persistedMetadata = TasteMapHybridRestaurantMetadata(
                tags: RestaurantCandidate.categoryLabels(contract?.tags ?? []),
                phone: contract?.phone,
                websiteUrl: contract?.websiteUrl,
                openingHours: contract?.openingHours,
                referencePrice: contract?.pricePerPerson,
                localUserPhotoID: preferredPhoto?.id,
                publicOrCachedPhotoID: contract?.markerPhotoId,
                providerMerchantImageURL: contract?.merchantImageUrl,
                localUserPhotoVisitID: preferredPhoto?.visitId.map { $0.uuidString.lowercased() },
                localUserPhotoVisibility: preferredPhoto?.visibility.rawValue,
                markerType: contract?.markerType.rawValue ?? "emoji",
                markerEmoji: contract?.markerEmoji ?? "🍽️"
            )
#endif
            let metadata = metadataByRestaurantID[restaurant.id] ?? persistedMetadata
            return restaurantDTO(
                restaurant,
                visits: restaurantVisits,
                metadata: metadata,
                status: visitedRestaurantIDs.contains(restaurant.id) ? .visited : .wantToGo
            )
        }
        projectedRestaurantSnapshot = snapshot
        return snapshot
    }

    private func ownedRestaurantDTO(_ restaurant: Restaurant) throws -> TasteMapHybridRestaurantDTO {
        let visits = try context.fetch(FetchDescriptor<Visit>()).filter {
            $0.ownerUserID == ownerUserID && $0.restaurantId == restaurant.id && $0.deletedAt == nil
        }.sorted {
            if $0.visitedAt != $1.visitedAt { return $0.visitedAt > $1.visitedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
#if TASTEMAP_HYBRID_BRIDGE_CORE
        let persistedMetadata = TasteMapHybridRestaurantMetadata()
#else
        let contract = restaurant.remoteRecordData.flatMap {
            try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0)
        }
        let photos = ownedVisitProjectionResources().photosByRestaurantID[restaurant.id] ?? []
        let preferredPhoto = contract?.markerType == .image
            ? RestaurantImagePhotoSelectionPolicy.preferredPhoto(
                restaurantID: restaurant.id,
                photos: photos,
                referencedPhotoID: contract?.markerPhotoId
            )
            : nil
        let persistedMetadata = TasteMapHybridRestaurantMetadata(
            tags: RestaurantCandidate.categoryLabels(contract?.tags ?? []),
            phone: contract?.phone,
            websiteUrl: contract?.websiteUrl,
            openingHours: contract?.openingHours,
            referencePrice: contract?.pricePerPerson,
            localUserPhotoID: preferredPhoto?.id,
            publicOrCachedPhotoID: contract?.markerPhotoId,
            providerMerchantImageURL: contract?.merchantImageUrl,
            localUserPhotoVisitID: preferredPhoto?.visitId.map { $0.uuidString.lowercased() },
            localUserPhotoVisibility: preferredPhoto?.visibility.rawValue,
            markerType: contract?.markerType.rawValue ?? "emoji",
            markerEmoji: contract?.markerEmoji ?? "🍽️"
        )
#endif
        let metadata = metadataByRestaurantID[restaurant.id] ?? persistedMetadata
        return restaurantDTO(
            restaurant,
            visits: visits,
            metadata: metadata,
            status: visits.isEmpty ? restaurant.status : .visited
        )
    }

    private func restaurantDTO(
        _ restaurant: Restaurant,
        visits: [Visit],
        metadata: TasteMapHybridRestaurantMetadata,
        status: RestaurantStatus
    ) -> TasteMapHybridRestaurantDTO {
        let rated = visits.compactMap(\.rating)
        let averageRating = rated.isEmpty ? nil : rounded(rated.reduce(0, +) / Double(rated.count), places: 1)
        let referencePrice = metadata.referencePrice ?? median(visits.compactMap(decimalDouble))
        let contentResolution = contentImageResolution(restaurant: restaurant, metadata: metadata, activeVisitIDs: Set(visits.map(\.id)))
        return TasteMapHybridRestaurantDTO(
            id: restaurant.remoteID ?? restaurant.id.uuidString.lowercased(),
            name: restaurant.name,
            address: restaurant.address,
            city: restaurant.city,
            latitude: restaurant.latitude,
            longitude: restaurant.longitude,
            status: status.rawValue,
            tags: RestaurantCandidate.categoryLabels(metadata.tags),
            phone: metadata.phone,
            websiteUrl: metadata.websiteUrl,
            openingHours: metadata.openingHours,
            referencePrice: referencePrice,
            visitCount: visits.count,
            averageRating: averageRating,
            scoreOutOfTen: averageRating.map { rounded($0 * 2, places: 1) },
            latestVisitDate: visits.first.map { Self.dateFormatter.string(from: $0.visitedAt) },
            createdAt: Self.dateFormatter.string(from: restaurant.createdAt),
            updatedAt: Self.dateFormatter.string(from: restaurant.updatedAt),
            visits: visits.map { visitDTO($0, restaurantID: restaurant.remoteID ?? restaurant.id.uuidString.lowercased()) },
            image: imageDescriptor(restaurant: restaurant, metadata: metadata),
            markerType: metadata.markerType,
            markerEmoji: metadata.markerEmoji,
            contentImage: contentResolution.sources.first ?? contentResolution.fallback,
            contentImageResolution: contentResolution
        )
    }

    private func visitDTO(_ visit: Visit, restaurantID: String) -> TasteMapHybridVisitDTO {
#if TASTEMAP_HYBRID_BRIDGE_CORE
        return TasteMapHybridVisitDTO(
            id: visit.remoteID ?? visit.id.uuidString.lowercased(),
            restaurantId: restaurantID,
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
        let resources = ownedVisitProjectionResources()
        let associations = resources.associationsByVisitID[visit.id] ?? []
        let dishes: [Dish]
        if associations.isEmpty {
            dishes = resources.dishesByVisitID[visit.id] ?? []
        } else {
            var seen = Set<UUID>()
            dishes = associations.compactMap { association in
                guard seen.insert(association.dishId).inserted else { return nil }
                return resources.dishesByID[association.dishId]
            }
        }
        let photos = resources.photosByVisitID[visit.id] ?? []
        return TasteMapHybridVisitDTO(
            id: visit.remoteID ?? visit.id.uuidString.lowercased(),
            restaurantId: restaurantID,
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
    private func ownedVisitProjectionResources() -> TasteMapHybridVisitProjectionResources {
        if let visitProjectionResources { return visitProjectionResources }
        let dishes = ((try? context.fetch(FetchDescriptor<Dish>())) ?? []).filter {
                $0.ownerUserID == ownerUserID && $0.deletedAt == nil
            }.sorted { $0.sortOrder < $1.sortOrder }
        let associations = ((try? context.fetch(FetchDescriptor<VisitDish>())) ?? []).filter {
                $0.ownerUserID == ownerUserID && $0.deletedAt == nil
            }.sorted { $0.sortOrder < $1.sortOrder }
        let photos = ((try? context.fetch(FetchDescriptor<PhotoAsset>())) ?? []).filter {
                $0.ownerUserID == ownerUserID && $0.deletedAt == nil && $0.binaryDeletedAt == nil
            }.sorted { $0.sortOrder < $1.sortOrder }
        let photosByRestaurantID = Dictionary(grouping: photos.compactMap { photo in
            photo.restaurantId.map { ($0, photo) }
        }, by: \.0).mapValues { $0.map(\.1) }
        let resources = TasteMapHybridVisitProjectionResources(
            dishesByID: Dictionary(uniqueKeysWithValues: dishes.map { ($0.id, $0) }),
            dishesByVisitID: Dictionary(grouping: dishes, by: \.visitId),
            associationsByVisitID: Dictionary(grouping: associations, by: \.visitId),
            photosByVisitID: Dictionary(grouping: photos.compactMap { photo in
                photo.visitId.map { ($0, photo) }
            }, by: \.0).mapValues { $0.map(\.1) },
            photosByRestaurantID: photosByRestaurantID
        )
        visitProjectionResources = resources
        return resources
    }

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
        // The saved marker type is the owner's visual choice. Do not let an old
        // marker photo or the Provider merchant image remain visually in front
        // after the owner selects any Emoji, including the generic plate Emoji.
        let usesOwnerEmoji = metadata.markerType == "emoji"
        if usesOwnerEmoji {
            return categoryDescriptor(
                name: restaurant.name,
                tags: RestaurantCandidate.categoryLabels(metadata.tags),
                seed: restaurant.id.uuidString.lowercased(),
                preferredEmoji: metadata.markerEmoji
            )
        }
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
        case .providerMerchantImage(let url):
            return TasteMapHybridImageDescriptor(
                kind: .providerMerchant,
                resourceURL: url.absoluteString,
                restaurantID: restaurant.remoteID ?? restaurant.id.uuidString.lowercased(),
                exportAllowed: false,
                attributionRequired: false,
                accessibilityLabel: label
            )
        case .foodDiningFallback:
            return debugCategoryDescriptor(
                name: restaurant.name,
                tags: RestaurantCandidate.categoryLabels(metadata.tags),
                seed: restaurant.id.uuidString.lowercased()
            )
        }
    }

    private func contentImageResolution(
        restaurant: Restaurant, metadata: TasteMapHybridRestaurantMetadata, activeVisitIDs: Set<UUID>
    ) -> TasteMapHybridImageResolutionDTO {
        let fallback = categoryDescriptor(name: restaurant.name, tags: RestaurantCandidate.categoryLabels(metadata.tags),
                                          seed: restaurant.remoteID ?? restaurant.id.uuidString.lowercased())
#if TASTEMAP_HYBRID_BRIDGE_CORE
        return .init(sources: [], fallback: fallback)
#else
        let resources = ownedVisitProjectionResources()
        let photos = RestaurantImagePhotoSelectionPolicy.actualPhotos(
            restaurantID: restaurant.id, photos: resources.photosByRestaurantID[restaurant.id] ?? []
        ).filter { $0.visitId.map(activeVisitIDs.contains) ?? true }
        let sources: [TasteMapHybridImageDescriptor] = photos.map { photo in
            let id = photo.remoteID ?? photo.id.uuidString.lowercased()
            return .init(kind: .ownerPhoto, resourceURL: "tastemap-resource://photo/\(id)/display",
                         photoID: id, restaurantID: restaurant.remoteID ?? restaurant.id.uuidString.lowercased(),
                         visitID: photo.visitId.map { $0.uuidString.lowercased() }, sourceOwnerID: ownerUserID,
                         visibility: photo.visibility.rawValue, exportAllowed: true,
                         attributionRequired: false, accessibilityLabel: "\(restaurant.name) 用户实拍")
        }
        return .init(sources: sources, fallback: fallback)
#endif
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

    private static func distanceMeters(
        _ item: TasteMapHybridRestaurantDTO,
        from origin: TasteMapHybridMapCoordinate
    ) -> Double {
        let earthRadius = 6_371_000.0
        let latitudeDelta = (item.latitude - origin.latitude) * .pi / 180
        let longitudeDelta = (item.longitude - origin.longitude) * .pi / 180
        let originLatitude = origin.latitude * .pi / 180
        let itemLatitude = item.latitude * .pi / 180
        let a = pow(sin(latitudeDelta / 2), 2)
            + cos(originLatitude) * cos(itemLatitude) * pow(sin(longitudeDelta / 2), 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }

    private static func scoreBand(_ score: Double?) -> Int? {
        guard let score, score.isFinite else { return nil }
        if score >= 9 { return 5 }
        if score >= 7 { return 4 }
        if score >= 5 { return 3 }
        if score >= 3 { return 2 }
        return 1
    }

    private static func price(_ value: Double?, matches range: String) -> Bool {
        guard let value, value.isFinite else { return false }
        switch range {
        case "under100": return value < 100
        case "100to200": return value >= 100 && value <= 200
        case "over200": return value > 200
        default: return false
        }
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
    var socialStats: TasteMapHybridRestaurantSocialStatsDTO? = nil
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
            tags: candidate.categoryHints,
            pricePerPerson: nil,
            merchantImageUrl: candidate.photoURL?.absoluteString,
            markerEmoji: "",
            photo: nil,
            phone: candidate.phone,
            websiteUrl: candidate.websiteURL?.absoluteString,
            openingHours: candidate.openingHours
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
