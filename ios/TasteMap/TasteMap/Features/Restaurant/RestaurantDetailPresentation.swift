import Foundation

struct RestaurantDetailPresentation {
    let activeVisits: [Visit]

    init(restaurantID: UUID, visits: [Visit]) {
        activeVisits = visits
            .filter { $0.restaurantId == restaurantID && $0.deletedAt == nil }
            .sorted { left, right in
                if left.visitedAt == right.visitedAt {
                    return left.createdAt > right.createdAt
                }
                return left.visitedAt > right.visitedAt
            }
    }

    var visitCount: Int { activeVisits.count }

    var averageRating: Double? {
        let ratings = activeVisits.compactMap(\.rating)
        guard !ratings.isEmpty else { return nil }
        return ratings.reduce(0, +) / Double(ratings.count)
    }

    var ratedVisitCount: Int { activeVisits.compactMap(\.rating).count }

    var latestVisit: Visit? { activeVisits.first }

    var totalSpend: Decimal? {
        let values = activeVisits.compactMap(\.myActualSpend)
        guard !values.isEmpty else { return nil }
        return values.reduce(.zero, +)
    }

    var averageSpend: Decimal? {
        let values = activeVisits.compactMap(\.myActualSpend)
        guard !values.isEmpty else { return nil }
        return values.reduce(.zero, +) / Decimal(values.count)
    }

    var queueSummary: RestaurantQueueSummary? {
        let values = activeVisits.compactMap { $0.queueDuration?.approximateMinutes }
        guard !values.isEmpty else { return nil }
        let average = Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
        return RestaurantQueueSummary(averageMinutes: average, sampleCount: values.count)
    }

    var tagGroups: [RestaurantExperienceTagGroup] {
        [
            tagGroup(title: "用餐场景", systemImage: "person.2.fill") {
                $0.diningOccasionDisplayTitles
            },
            tagGroup(title: "性价比", systemImage: "yensign.circle.fill", values: \.valueTags),
            tagGroup(title: "环境", systemImage: "leaf.fill", values: \.environmentTags),
            tagGroup(title: "服务", systemImage: "hand.raised.fill", values: \.serviceTags),
        ].filter { !$0.tags.isEmpty }
    }

    private func tagGroup(
        title: String,
        systemImage: String,
        values: (Visit) -> [String]
    ) -> RestaurantExperienceTagGroup {
        var counts: [String: Int] = [:]
        for visit in activeVisits {
            for value in Set(values(visit).map(Self.normalizedTag).filter { !$0.isEmpty }) {
                counts[value, default: 0] += 1
            }
        }
        let tags = counts.map { RestaurantExperienceTag(label: $0.key, count: $0.value) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.label.localizedStandardCompare($1.label) == .orderedAscending
            }
            .prefix(6)
        return RestaurantExperienceTagGroup(
            title: title,
            systemImage: systemImage,
            tags: Array(tags)
        )
    }

    private func tagGroup(
        title: String,
        systemImage: String,
        values: KeyPath<Visit, [String]>
    ) -> RestaurantExperienceTagGroup {
        tagGroup(title: title, systemImage: systemImage) { $0[keyPath: values] }
    }

    nonisolated private static func normalizedTag(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct RestaurantQueueSummary: Equatable {
    let averageMinutes: Int
    let sampleCount: Int
}

struct RestaurantExperienceTag: Identifiable, Equatable {
    let label: String
    let count: Int
    var id: String { label }
}

struct RestaurantExperienceTagGroup: Identifiable, Equatable {
    let title: String
    let systemImage: String
    let tags: [RestaurantExperienceTag]
    var id: String { title }
}

struct RestaurantDetailMetadata: Equatable {
    let ownerUserID: String?
    let storedPhone: String?
    let openingHours: String?
    let referencePrice: Decimal?
    let longTermNote: String?
    let merchantImageURL: URL?
    let markerPhotoID: String?
    let markerEmoji: String
    let markerType: RestaurantJSONContractV1.RestaurantMarkerTypeContract
    let globalIdentityKeys: Set<String>

    @MainActor
    init(restaurant: Restaurant) {
        let record = restaurant.remoteRecordData.flatMap {
            try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0)
        }
        ownerUserID = Self.trimmed(record?.userId)
        storedPhone = Self.trimmed(record?.phone)
        openingHours = Self.trimmed(record?.openingHours)
        if let price = record?.pricePerPerson, price.isFinite, price > 0 {
            referencePrice = Decimal(price)
        } else {
            referencePrice = nil
        }
        longTermNote = Self.trimmed(record?.longTermNote)
        merchantImageURL = Self.safeHTTPSURL(record?.merchantImageUrl)
        markerPhotoID = Self.trimmed(record?.markerPhotoId)
        markerEmoji = Self.trimmed(record?.markerEmoji) ?? "🍽️"
        markerType = record?.markerType ?? .emoji

        var keys = Set(record?.placeIdentities.map {
            "\($0.provider.rawValue):\($0.externalId)"
        } ?? [])
        if let appleID = Self.trimmed(restaurant.appleMapItemIdentifier) {
            keys.insert("apple_maps:\(appleID)")
        }
        globalIdentityKeys = keys
    }

    init(projection: DiscoveryRestaurantProjectionV1) {
        ownerUserID = nil
        storedPhone = nil
        openingHours = nil
        if let price = projection.pricePerPerson, price.isFinite, price > 0 {
            referencePrice = Decimal(price)
        } else {
            referencePrice = nil
        }
        longTermNote = nil
        merchantImageURL = Self.safeHTTPSURL(projection.merchantImageUrl)
        markerPhotoID = projection.photo?.photoId
        markerEmoji = Self.trimmed(projection.markerEmoji) ?? "🍽️"
        markerType = .emoji
        globalIdentityKeys = Set(
            projection.placeIdentities.map { "\($0.provider.rawValue):\($0.externalId)" }
        )
    }

    var callablePhone: String? {
        guard let storedPhone, RestaurantPhoneDialing.url(for: storedPhone) != nil else { return nil }
        return storedPhone
    }

    var hasBusinessInformation: Bool {
        callablePhone != nil || openingHours != nil || referencePrice != nil || longTermNote != nil
    }

    static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func safeHTTPSURL(_ value: String?) -> URL? {
        guard let value = trimmed(value), let url = URL(string: value),
              url.scheme?.lowercased() == "https", url.host?.isEmpty == false else { return nil }
        return url
    }
}

enum RestaurantPhoneDialing {
    nonisolated static func url(for value: String?) -> URL? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var normalized = ""
        var digitCount = 0
        for character in trimmed {
            if character.isASCII, character.isNumber {
                normalized.append(character)
                digitCount += 1
            } else if character == "+", normalized.isEmpty {
                normalized.append(character)
            } else if [" ", "-", "(", ")"].contains(character) {
                continue
            } else {
                return nil
            }
        }
        guard (3...15).contains(digitCount) else { return nil }
        return URL(string: "tel:\(normalized)")
    }
}

struct RestaurantRatingReference: Identifiable, Equatable {
    let title: String
    let value: Double
    let sampleCount: Int
    let systemImage: String
    var id: String { title }
}

@MainActor
enum RestaurantRatingReferenceResolver {
    static func resolve(
        metadata: RestaurantDetailMetadata,
        currentUserID: String?,
        placements: [CachedDiscoveryPlacement]
    ) -> [RestaurantRatingReference] {
        guard let currentUserID, !metadata.globalIdentityKeys.isEmpty else { return [] }
        let contexts = placements
            .filter {
                $0.currentUserID == currentUserID &&
                    metadata.globalIdentityKeys.contains($0.globalKey)
            }
            .sorted(by: { $0.generatedAt > $1.generatedAt })
            .compactMap(\.context)
        guard let context = contexts.first else { return [] }

        return [
            reference(title: "全部用户评分", rating: context.ratings.community, systemImage: "person.3.fill"),
            reference(title: "好友评分", rating: context.ratings.friends, systemImage: "person.2.fill"),
            reference(title: "同味评分", rating: context.ratings.similarTaste, systemImage: "person.2.wave.2.fill"),
        ].compactMap { $0 }
    }

    private static func reference(
        title: String,
        rating: DiscoveryRatingProjectionV1,
        systemImage: String
    ) -> RestaurantRatingReference? {
        guard let value = rating.value, value.isFinite, (0...5).contains(value),
              rating.sampleCount > 0 else { return nil }
        return RestaurantRatingReference(
            title: title,
            value: value,
            sampleCount: rating.sampleCount,
            systemImage: systemImage
        )
    }
}

enum RestaurantDetailImageSource: Equatable {
    case ownedPhoto(UUID)
    case merchant(URL)
    case brand(String)
}

@MainActor
enum RestaurantDetailImageResolver {
    static func visibleRestaurantPhotos(
        _ photos: [PhotoAsset],
        restaurantID: UUID,
        activeVisitIDs: Set<UUID>
    ) -> [PhotoAsset] {
        photos.filter { photo in
            guard photo.restaurantId == restaurantID,
                  photo.deletedAt == nil,
                  photo.binaryDeletedAt == nil,
                  [.restaurantMarker, .visit, .dish].contains(photo.kind) else { return false }
            return photo.visitId.map(activeVisitIDs.contains) ?? true
        }
    }

    static func orderedPhotos(
        _ photos: [PhotoAsset],
        metadata: RestaurantDetailMetadata
    ) -> [PhotoAsset] {
        photos.sorted { left, right in
            let leftRank = rank(left, markerPhotoID: metadata.markerPhotoID)
            let rightRank = rank(right, markerPhotoID: metadata.markerPhotoID)
            if leftRank != rightRank { return leftRank < rightRank }
            if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
            return left.sortOrder < right.sortOrder
        }
    }

    static func preferredSource(
        photos: [PhotoAsset],
        metadata: RestaurantDetailMetadata
    ) -> RestaurantDetailImageSource {
        if let photo = orderedPhotos(photos, metadata: metadata).first {
            return .ownedPhoto(photo.id)
        }
        if let url = metadata.merchantImageURL { return .merchant(url) }
        return .brand(metadata.markerEmoji)
    }

    private static func rank(_ photo: PhotoAsset, markerPhotoID: String?) -> Int {
        if let markerPhotoID,
           photo.remoteID == markerPhotoID || photo.id.uuidString.lowercased() == markerPhotoID.lowercased() {
            return 0
        }
        return photo.kind == .restaurantMarker ? 1 : 2
    }
}

enum RestaurantDetailFormatting {
    nonisolated static func currency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
    }

    nonisolated static func referencePrice(_ value: Decimal) -> String {
        "\(currency(value)) / 人"
    }

    nonisolated static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day())
    }
}
