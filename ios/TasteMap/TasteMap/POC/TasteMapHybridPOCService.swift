import Foundation
import SwiftData

public enum TasteMapHybridPOCError: LocalizedError {
    case fixtureInvalid
    case profileMissing
    case restaurantMissing(String)

    public var errorDescription: String? {
        switch self {
        case .fixtureInvalid: "The deterministic POC fixture is invalid."
        case .profileMissing: "The isolated SwiftData profile is missing."
        case .restaurantMissing(let id): "Restaurant \(id) is missing from isolated SwiftData."
        }
    }
}

/// POC-only facade over the current Taste Map SwiftData schema.
///
/// It seeds a fresh in-memory container, then every bridge response is rebuilt
/// from a SwiftData fetch. It never opens the shipping store, Keychain, network,
/// Worker, or a real user's records.
@MainActor
public final class TasteMapHybridPOCService {
    public static let bridgeVersion = 1
    private static let ownerID = "tm_capacitor_poc"

    private let container: ModelContainer
    private let context: ModelContext
    private var fixtureRoot: [String: Any] = [:]

    public init() throws {
        let schema = Schema([
            Restaurant.self,
            Visit.self,
            UserProfile.self,
            CachedFollow.self,
        ])
        let configuration = ModelConfiguration(
            "TasteMapHybridPOC",
            schema: schema,
            isStoredInMemoryOnly: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    public func bootstrap(fixtureData: Data) throws {
        guard fixtureRoot.isEmpty,
              let root = try JSONSerialization.jsonObject(with: fixtureData) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let user = profile["user"] as? [String: Any],
              let restaurants = root["restaurants"] as? [[String: Any]] else {
            if fixtureRoot.isEmpty { throw TasteMapHybridPOCError.fixtureInvalid }
            return
        }
        fixtureRoot = root

        let nativeProfile = UserProfile(
            tasteMapUserID: Self.ownerID,
            displayName: string(user, "nickname") ?? "Taste Map POC",
            bio: string(user, "bio") ?? "",
            city: string(user, "city") ?? "",
            avatarPreset: ProfileAvatarPreset(rawValue: string(user, "avatarPresetId") ?? "otter") ?? .otter,
            visibility: .friends,
            createdAt: date(user["createdAt"]) ?? .now,
            updatedAt: date(user["updatedAt"]) ?? .now,
            syncStatus: .synced
        )
        context.insert(nativeProfile)

        for fixture in restaurants {
            guard let idValue = string(fixture, "id"), let id = UUID(uuidString: idValue) else { continue }
            let status = RestaurantStatus(rawValue: string(fixture, "status") ?? "visited") ?? .visited
            let model = Restaurant(
                id: id,
                ownerUserID: Self.ownerID,
                name: string(fixture, "name") ?? "未命名餐厅",
                address: string(fixture, "address") ?? "",
                latitude: number(fixture["latitude"]) ?? 0,
                longitude: number(fixture["longitude"]) ?? 0,
                city: string(fixture, "city") ?? "",
                status: status,
                createdAt: date(fixture["createdAt"]) ?? .now,
                updatedAt: date(fixture["updatedAt"]) ?? .now,
                remoteID: idValue,
                serverVersion: 1,
                lastSyncedAt: .now,
                syncStatus: .synced
            )
            context.insert(model)

            for visitFixture in fixture["visits"] as? [[String: Any]] ?? [] {
                guard let visitIDValue = string(visitFixture, "id"), let visitID = UUID(uuidString: visitIDValue) else { continue }
                let visit = Visit(
                    id: visitID,
                    ownerUserID: Self.ownerID,
                    restaurantId: id,
                    visitedAt: date(visitFixture["visitedAt"]) ?? .now,
                    rating: number(visitFixture["rating"]),
                    valueRating: number(visitFixture["valueRating"]),
                    environmentRating: number(visitFixture["environmentRating"]),
                    serviceRating: number(visitFixture["serviceRating"]),
                    note: string(visitFixture, "note"),
                    myActualSpend: decimal(visitFixture["myActualSpend"]),
                    totalPrice: decimal(visitFixture["totalPrice"]),
                    pricePerPerson: decimal(visitFixture["pricePerPerson"]),
                    diningMode: DiningMode(rawValue: string(visitFixture, "diningMode") ?? "dine_in") ?? .dineIn,
                    visibility: VisitVisibility(rawValue: string(visitFixture, "visibility") ?? "private") ?? .private,
                    paymentMode: string(visitFixture, "paymentMode").flatMap(VisitPaymentMode.init(rawValue:)),
                    queueDuration: string(visitFixture, "queueDuration").flatMap(VisitQueueDuration.init(rawValue:)),
                    diningOccasions: strings(visitFixture["diningOccasions"]).compactMap(VisitDiningOccasion.init(rawValue:)),
                    diningOccasionText: string(visitFixture, "diningOccasionText"),
                    valueTags: strings(visitFixture["valueTags"]),
                    environmentTags: strings(visitFixture["environmentTags"]),
                    serviceTags: strings(visitFixture["serviceTags"]),
                    companionIDs: strings(visitFixture["companionIds"]),
                    companionNames: strings(visitFixture["companions"]),
                    recommendationSourceText: string(visitFixture, "recommendationSourceText"),
                    partySize: integer(visitFixture["partySize"]),
                    createdAt: date(visitFixture["createdAt"]) ?? .now,
                    updatedAt: date(visitFixture["updatedAt"]) ?? .now,
                    remoteID: visitIDValue,
                    serverVersion: 1,
                    lastSyncedAt: .now,
                    syncStatus: .synced
                )
                context.insert(visit)
            }
        }

        let followingCount = integer(profile["followingCount"]) ?? 0
        let followerCount = integer(profile["followerCount"]) ?? 0
        for index in 0..<followingCount {
            context.insert(CachedFollow(
                relationshipID: "poc-following-\(index)",
                currentUserID: Self.ownerID,
                followerUserID: Self.ownerID,
                followedUserID: "tm_followed_\(index)",
                serverVersion: 1
            ))
        }
        for index in 0..<followerCount {
            context.insert(CachedFollow(
                relationshipID: "poc-follower-\(index)",
                currentUserID: Self.ownerID,
                followerUserID: "tm_follower_\(index)",
                followedUserID: Self.ownerID,
                serverVersion: 1
            ))
        }
        try context.save()
    }

    public func runtimeJSON() throws -> String {
        try jsonString([
            "bridgeVersion": Self.bridgeVersion,
            "platform": "ios",
            "dataSource": "native-swiftdata-in-memory",
            "localBundle": true,
            "offlineCapable": true,
        ])
    }

    public func profileJSON() throws -> String {
        guard let profile = try context.fetch(FetchDescriptor<UserProfile>())
            .first(where: { $0.tasteMapUserID == Self.ownerID && $0.deletedAt == nil }) else {
            throw TasteMapHybridPOCError.profileMissing
        }
        let restaurants = try nativeRestaurantDictionaries()
        let visits = restaurants.flatMap { $0["visits"] as? [[String: Any]] ?? [] }
        let follows = try context.fetch(FetchDescriptor<CachedFollow>()).filter {
            $0.currentUserID == Self.ownerID && $0.deletedAt == nil
        }
        return try jsonString([
            "user": userDictionary(profile),
            "restaurants": restaurants,
            "visits": visits,
            "followingCount": follows.filter { $0.followerUserID == Self.ownerID }.count,
            "followerCount": follows.filter { $0.followedUserID == Self.ownerID }.count,
        ])
    }

    public func restaurantJSON(id: String) throws -> String {
        guard let dictionary = try nativeRestaurantDictionaries().first(where: { string($0, "id") == id }) else {
            throw TasteMapHybridPOCError.restaurantMissing(id)
        }
        return try jsonString(dictionary)
    }

    private func nativeRestaurantDictionaries() throws -> [[String: Any]] {
        let fixtures = fixtureRoot["restaurants"] as? [[String: Any]] ?? []
        let fixtureByID = Dictionary(uniqueKeysWithValues: fixtures.compactMap { fixture -> (String, [String: Any])? in
            guard let id = string(fixture, "id") else { return nil }
            return (id, fixture)
        })
        let restaurants = try context.fetch(FetchDescriptor<Restaurant>())
            .filter { $0.ownerUserID == Self.ownerID && $0.deletedAt == nil }
        let visits = try context.fetch(FetchDescriptor<Visit>())
            .filter { $0.ownerUserID == Self.ownerID && $0.deletedAt == nil }

        return restaurants.sorted { $0.createdAt < $1.createdAt }.compactMap { restaurant in
            let id = restaurant.remoteID ?? restaurant.id.uuidString
            guard var output = fixtureByID[id] else { return nil }
            output["id"] = id
            output["userId"] = restaurant.ownerUserID
            output["name"] = restaurant.name
            output["address"] = restaurant.address
            output["city"] = restaurant.city
            output["latitude"] = restaurant.latitude
            output["longitude"] = restaurant.longitude
            output["status"] = restaurant.status.rawValue
            output["createdAt"] = iso8601(restaurant.createdAt)
            output["updatedAt"] = iso8601(restaurant.updatedAt)
            let nativeVisits = visits.filter { $0.restaurantId == restaurant.id }.sorted { $0.visitedAt > $1.visitedAt }
            let fixtureVisits = Dictionary(uniqueKeysWithValues: ((output["visits"] as? [[String: Any]]) ?? []).compactMap { item -> (String, [String: Any])? in
                guard let id = string(item, "id") else { return nil }
                return (id, item)
            })
            output["visits"] = nativeVisits.map { nativeVisitDictionary($0, fixture: fixtureVisits[$0.remoteID ?? $0.id.uuidString] ?? [:]) }
            output["visitCount"] = nativeVisits.count
            output["latestVisitDate"] = nativeVisits.first.map { iso8601($0.visitedAt) } ?? NSNull()

            let resolution = RestaurantImagePriorityPolicy.resolution(
                localUserPhotoID: nil,
                publicOrCachedPhotoID: nil,
                providerMerchantImageURL: string(output, "merchantImageUrl")
            )
            switch resolution.preferredSource {
            case .providerMerchantImage(let url):
                output["merchantImageUrl"] = url.absoluteString
                output["_nativeImageSource"] = "providerMerchantImage"
            case .localUserPhoto:
                output["_nativeImageSource"] = "localUserPhoto"
            case .publicOrCachedPhoto:
                output["_nativeImageSource"] = "publicOrCachedPhoto"
            case .foodDiningFallback:
                output["merchantImageUrl"] = NSNull()
                output["_nativeImageSource"] = "foodDiningFallback"
            }
            return output
        }
    }

    private func userDictionary(_ profile: UserProfile) -> [String: Any] {
        var user = ((fixtureRoot["profile"] as? [String: Any])?["user"] as? [String: Any]) ?? [:]
        user["id"] = profile.tasteMapUserID
        user["nickname"] = profile.displayName
        user["bio"] = profile.bio
        user["city"] = profile.city
        user["avatarPresetId"] = profile.avatarPreset.rawValue
        user["createdAt"] = iso8601(profile.createdAt)
        user["updatedAt"] = iso8601(profile.updatedAt)
        return user
    }

    private func nativeVisitDictionary(_ visit: Visit, fixture: [String: Any]) -> [String: Any] {
        var output = fixture
        output["id"] = visit.remoteID ?? visit.id.uuidString
        output["userId"] = visit.ownerUserID
        output["restaurantId"] = visit.restaurantId.uuidString.lowercased()
        output["visitedAt"] = iso8601(visit.visitedAt)
        output["rating"] = jsonValue(visit.rating)
        output["valueRating"] = jsonValue(visit.valueRating)
        output["environmentRating"] = jsonValue(visit.environmentRating)
        output["serviceRating"] = jsonValue(visit.serviceRating)
        output["note"] = visit.note ?? ""
        output["myActualSpend"] = decimalNumber(visit.myActualSpend)
        output["totalPrice"] = decimalNumber(visit.totalPrice)
        output["pricePerPerson"] = decimalNumber(visit.pricePerPerson)
        output["diningMode"] = visit.diningMode.rawValue
        output["visibility"] = visit.visibility.rawValue
        output["paymentMode"] = visit.paymentModeRawValue ?? NSNull()
        output["queueDuration"] = visit.queueDurationRawValue ?? NSNull()
        output["diningOccasions"] = visit.diningOccasionRawValues
        output["valueTags"] = visit.valueTags
        output["environmentTags"] = visit.environmentTags
        output["serviceTags"] = visit.serviceTags
        output["companions"] = visit.companionNames
        output["companionIds"] = visit.companionIDs
        output["partySize"] = visit.partySize ?? NSNull()
        output["createdAt"] = iso8601(visit.createdAt)
        output["updatedAt"] = iso8601(visit.updatedAt)
        return output
    }

    private func jsonString(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let value = String(data: data, encoding: .utf8) else { throw TasteMapHybridPOCError.fixtureInvalid }
        return value
    }

    private func string(_ dictionary: [String: Any], _ key: String) -> String? {
        Self.string(dictionary, key)
    }

    private static func string(_ dictionary: [String: Any], _ key: String) -> String? {
        dictionary[key] as? String
    }

    private func number(_ value: Any?) -> Double? { Self.number(value) }
    private static func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
    private func integer(_ value: Any?) -> Int? { Self.integer(value) }
    private static func integer(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }
    private func strings(_ value: Any?) -> [String] { value as? [String] ?? [] }
    private func decimal(_ value: Any?) -> Decimal? { number(value).map { Decimal($0) } }
    private func decimalNumber(_ value: Decimal?) -> Any { value.map { NSDecimalNumber(decimal: $0) } ?? NSNull() }
    private func jsonValue(_ value: Double?) -> Any { value.map(NSNumber.init(value:)) ?? NSNull() }
    private func date(_ value: Any?) -> Date? { (value as? String).flatMap(Self.formatter.date(from:)) }
    private func iso8601(_ value: Date) -> String { Self.formatter.string(from: value) }

    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
