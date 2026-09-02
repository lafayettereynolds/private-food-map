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

    public init(
        tags: [String] = [],
        phone: String? = nil,
        openingHours: String? = nil,
        referencePrice: Double? = nil,
        localUserPhotoID: UUID? = nil,
        publicOrCachedPhotoID: String? = nil,
        providerMerchantImageURL: String? = nil
    ) {
        self.tags = tags
        self.phone = phone
        self.openingHours = openingHours
        self.referencePrice = referencePrice
        self.localUserPhotoID = localUserPhotoID
        self.publicOrCachedPhotoID = publicOrCachedPhotoID
        self.providerMerchantImageURL = providerMerchantImageURL
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

    public init(
        container: ModelContainer,
        ownerUserID: String,
        membershipTier: String = "free",
        mapSharingEnabled: Bool = false,
        metadataByRestaurantID: [UUID: TasteMapHybridRestaurantMetadata] = [:]
    ) throws {
        let normalizedOwner = LocalAccountOwner.normalized(ownerUserID)
        guard normalizedOwner.hasPrefix("tm_") else { throw TasteMapHybridServiceError.authRequired }
        self.ownerUserID = normalizedOwner
        self.context = ModelContext(container)
        self.context.autosaveEnabled = false
        self.membershipTier = membershipTier == "member" ? "member" : "free"
        self.mapSharingEnabled = mapSharingEnabled
        self.metadataByRestaurantID = metadataByRestaurantID
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
        guard let restaurant = try scopedRestaurants().first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) else {
            throw TasteMapHybridServiceError.restaurantMissing
        }
        return TasteMapHybridRestaurantDetailDTO(restaurant: restaurant)
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
            .map(TasteMapHybridRestaurantDetailDTO.init(restaurant:))
    }

    private func scopedRestaurants() throws -> [TasteMapHybridRestaurantDTO] {
        let restaurants = try context.fetch(FetchDescriptor<Restaurant>()).filter {
            $0.ownerUserID == ownerUserID && $0.deletedAt == nil
        }
        let visits = try context.fetch(FetchDescriptor<Visit>()).filter {
            $0.ownerUserID == ownerUserID && $0.deletedAt == nil
        }
        let visitsByRestaurant = Dictionary(grouping: visits, by: \Visit.restaurantId)
        return restaurants.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }.map { restaurant in
            let restaurantVisits = (visitsByRestaurant[restaurant.id] ?? []).sorted {
                if $0.visitedAt != $1.visitedAt { return $0.visitedAt > $1.visitedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            let rated = restaurantVisits.compactMap(\.rating)
            let averageRating = rated.isEmpty ? nil : rounded(rated.reduce(0, +) / Double(rated.count), places: 1)
            let metadata = metadataByRestaurantID[restaurant.id] ?? TasteMapHybridRestaurantMetadata()
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
    }

    private func visitDTO(_ visit: Visit) -> TasteMapHybridVisitDTO {
        TasteMapHybridVisitDTO(
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
            companions: visit.companionNames,
            companionIds: visit.companionIDs,
            recommendationSourceText: visit.recommendationSourceText ?? "",
            partySize: visit.partySize,
            note: visit.note ?? "",
            createdAt: Self.dateFormatter.string(from: visit.createdAt),
            updatedAt: Self.dateFormatter.string(from: visit.updatedAt)
        )
    }

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
                kind: .nativeResource,
                resourceURL: "tastemap-resource://photo/\(id.uuidString.lowercased())/display",
                photoID: id.uuidString.lowercased(),
                accessibilityLabel: label
            )
        case .publicOrCachedPhoto(let id):
            let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
            return TasteMapHybridImageDescriptor(
                kind: .publicOrCached,
                resourceURL: "tastemap-resource://public-photo/\(encoded)/display",
                photoID: id,
                accessibilityLabel: label
            )
        case .providerMerchantImage(let url):
            return TasteMapHybridImageDescriptor(kind: .providerMerchant, resourceURL: url.absoluteString, accessibilityLabel: label)
        case .foodDiningFallback:
            return TasteMapHybridImageDescriptor(kind: .foodDiningFallback, stableSeed: restaurant.id.uuidString.lowercased(), accessibilityLabel: label)
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

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
