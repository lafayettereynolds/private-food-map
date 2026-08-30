import Foundation

nonisolated enum RouletteCandidateSource: String, CaseIterable, Identifiable, Sendable {
    case all
    case wantToGo
    case visited

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "全部"
        case .wantToGo: "想吃"
        case .visited: "去过"
        }
    }
}

nonisolated struct RouletteFilter: Equatable, Sendable {
    var source: RouletteCandidateSource = .all
    var city: String?
    var excludedGlobalKeys: Set<String> = []
}

nonisolated struct RouletteCandidate: Identifiable, Equatable, Hashable, Sendable {
    let restaurantID: UUID
    let globalKey: String
    let displayName: String
    let address: String
    let city: String
    let status: RestaurantStatus
    let averageRating: Double?
    let visitCount: Int
    let latestVisitAt: Date?
    let photoID: UUID?
    let categories: [String]
    let markerEmoji: String
    let updatedAt: Date

    var id: String { globalKey }

    var statusDetail: String {
        switch status {
        case .wantToGo:
            "还在你的想吃清单里"
        case .visited:
            visitCount > 0 ? "你已经去过 \(visitCount) 次" : "你记录为去过"
        }
    }
}

nonisolated struct RouletteRestaurantRecord: Equatable, Sendable {
    let restaurantID: UUID
    let globalKey: String
    let displayName: String
    let address: String
    let city: String
    let status: RestaurantStatus
    let updatedAt: Date
    let deletedAt: Date?
    let averageRating: Double?
    let visitCount: Int
    let latestVisitAt: Date?
    let photoID: UUID?
    let categories: [String]
    let markerEmoji: String
    let latitude: Double
    let longitude: Double
}

nonisolated enum RestaurantRouletteEngine {
    static let maximumActiveCandidateCount = 10

    static func candidates(from records: [RouletteRestaurantRecord]) -> [RouletteCandidate] {
        let valid = records.filter { record in
            record.deletedAt == nil
                && !record.globalKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !record.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && record.latitude.isFinite && (-90...90).contains(record.latitude)
                && record.longitude.isFinite && (-180...180).contains(record.longitude)
        }

        var newestByIdentity: [String: RouletteRestaurantRecord] = [:]
        for record in valid {
            let key = normalizedIdentity(record.globalKey)
            guard let current = newestByIdentity[key] else {
                newestByIdentity[key] = record
                continue
            }
            if record.updatedAt > current.updatedAt
                || (record.updatedAt == current.updatedAt
                    && record.restaurantID.uuidString < current.restaurantID.uuidString) {
                newestByIdentity[key] = record
            }
        }

        return newestByIdentity.values.map { record in
            RouletteCandidate(
                restaurantID: record.restaurantID,
                globalKey: record.globalKey,
                displayName: record.displayName,
                address: record.address,
                city: record.city.trimmingCharacters(in: .whitespacesAndNewlines),
                status: record.status,
                averageRating: record.averageRating,
                visitCount: record.visitCount,
                latestVisitAt: record.latestVisitAt,
                photoID: record.photoID,
                categories: stableUnique(record.categories),
                markerEmoji: record.markerEmoji.isEmpty ? "🍽️" : record.markerEmoji,
                updatedAt: record.updatedAt
            )
        }.sorted(by: stableOrder)
    }

    static func filtered(
        _ candidates: [RouletteCandidate],
        by filter: RouletteFilter
    ) -> [RouletteCandidate] {
        let city = normalizedText(filter.city ?? "")
        return candidates.filter { candidate in
            guard !filter.excludedGlobalKeys.contains(candidate.globalKey) else { return false }
            if !city.isEmpty, normalizedText(candidate.city) != city { return false }
            switch filter.source {
            case .all: return true
            case .wantToGo: return candidate.status == .wantToGo
            case .visited: return candidate.status == .visited
            }
        }.sorted(by: stableOrder)
    }

    static func defaultCity(
        for candidates: [RouletteCandidate],
        preferredCity: String?
    ) -> String? {
        let available = candidates.map(\.city).filter { !$0.isEmpty }
        guard !available.isEmpty else { return nil }
        if let preferred = preferredCity?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preferred.isEmpty,
           let matching = available.first(where: { normalizedText($0) == normalizedText(preferred) }) {
            return matching
        }
        let grouped = Dictionary(grouping: available, by: normalizedText)
        return grouped.sorted { left, right in
            if left.value.count != right.value.count { return left.value.count > right.value.count }
            return left.key.localizedStandardCompare(right.key) == .orderedAscending
        }.first?.value.sorted(by: localizedAscending).first
    }

    static func cities(in candidates: [RouletteCandidate]) -> [String] {
        let grouped = Dictionary(grouping: candidates.map(\.city).filter { !$0.isEmpty }, by: normalizedText)
        return grouped.values.compactMap { $0.sorted(by: localizedAscending).first }
            .sorted(by: localizedAscending)
    }

    static func select<R: RandomNumberGenerator>(
        from candidates: [RouletteCandidate],
        excludingImmediateRepeat lastGlobalKey: String?,
        using generator: inout R
    ) -> RouletteCandidate? {
        guard !candidates.isEmpty else { return nil }
        let eligible: [RouletteCandidate]
        if candidates.count > 1, let lastGlobalKey {
            let withoutLast = candidates.filter { $0.globalKey != lastGlobalKey }
            eligible = withoutLast.isEmpty ? candidates : withoutLast
        } else {
            eligible = candidates
        }
        return eligible.randomElement(using: &generator)
    }

    static func select(
        from candidates: [RouletteCandidate],
        excludingImmediateRepeat lastGlobalKey: String?
    ) -> RouletteCandidate? {
        var generator = SystemRandomNumberGenerator()
        return select(
            from: candidates,
            excludingImmediateRepeat: lastGlobalKey,
            using: &generator
        )
    }

    static func defaultActiveGlobalKeys(
        from candidates: [RouletteCandidate],
        preferredGlobalKey: String? = nil
    ) -> Set<String> {
        var ordered = candidates
        if let preferredGlobalKey,
           let preferredIndex = ordered.firstIndex(where: { $0.globalKey == preferredGlobalKey }) {
            let preferred = ordered.remove(at: preferredIndex)
            ordered.insert(preferred, at: 0)
        }
        return Set(ordered.prefix(maximumActiveCandidateCount).map(\.globalKey))
    }

    static func activeCandidates(
        from candidates: [RouletteCandidate],
        selectedGlobalKeys: Set<String>
    ) -> [RouletteCandidate] {
        Array(candidates.filter { selectedGlobalKeys.contains($0.globalKey) }
            .prefix(maximumActiveCandidateCount))
    }

    static func visualSegmentCount(candidateCount: Int) -> Int {
        max(0, candidateCount)
    }

    static func visualIndex(selectedIndex: Int, candidateCount: Int) -> Int {
        let count = visualSegmentCount(candidateCount: candidateCount)
        guard count > 0 else { return 0 }
        return max(0, selectedIndex) % count
    }

    static func targetRotation(
        currentRotation: Double,
        selectedIndex: Int,
        candidateCount: Int,
        fullTurns: Int = 5
    ) -> Double {
        let count = visualSegmentCount(candidateCount: candidateCount)
        guard count > 0 else { return currentRotation }
        let segment = 360 / Double(count)
        let index = visualIndex(selectedIndex: selectedIndex, candidateCount: candidateCount)
        let target = 360 - (Double(index) + 0.5) * segment
        let completedTurns = ceil(max(0, currentRotation) / 360) * 360
        return completedTurns + Double(max(1, fullTurns)) * 360 + target
    }

    static func pointerVisualIndex(finalRotation: Double, visualSegmentCount: Int) -> Int? {
        guard visualSegmentCount > 0 else { return nil }
        let normalizedRotation = positiveModulo(finalRotation, 360)
        let pointerAngleInWheel = positiveModulo(360 - normalizedRotation, 360)
        let segment = 360 / Double(visualSegmentCount)
        return min(visualSegmentCount - 1, Int(pointerAngleInWheel / segment))
    }

    static func abbreviatedName(_ name: String, candidateCount: Int) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutBranch = trimmed.replacingOccurrences(
            of: #"[（(][^）)]*[）)]"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = withoutBranch.isEmpty ? trimmed : withoutBranch
        let limit = candidateCount <= 6 ? 6 : 4
        let characters = Array(value)
        return characters.count > limit
            ? String(characters.prefix(limit)) + "…"
            : value
    }

    private static func normalizedIdentity(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "zh_CN"))
    }

    private static func stableOrder(_ left: RouletteCandidate, _ right: RouletteCandidate) -> Bool {
        let nameOrder = left.displayName.localizedStandardCompare(right.displayName)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return left.globalKey < right.globalKey
    }

    private static func localizedAscending(_ left: String, _ right: String) -> Bool {
        left.localizedStandardCompare(right) == .orderedAscending
    }

    private static func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = normalizedText(trimmed)
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    private static func positiveModulo(_ value: Double, _ divisor: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: divisor)
        return result >= 0 ? result : result + divisor
    }
}

@MainActor
extension RouletteRestaurantRecord {
    static func capture(
        restaurants: [Restaurant],
        visits: [Visit],
        photos: [PhotoAsset]
    ) -> [RouletteRestaurantRecord] {
        let activeVisits = visits.filter { $0.deletedAt == nil }
        let visitsByRestaurant = Dictionary(grouping: activeVisits, by: \.restaurantId)
        let activePhotos = photos.filter { $0.deletedAt == nil && $0.binaryDeletedAt == nil }
        let photosByRestaurant = Dictionary(grouping: activePhotos.compactMap { photo in
            photo.restaurantId.map { ($0, photo) }
        }, by: \.0)

        return restaurants.map { restaurant in
            let contract = restaurant.remoteRecordData.flatMap {
                try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0)
            }
            let restaurantVisits = visitsByRestaurant[restaurant.id] ?? []
            let ratings = restaurantVisits.compactMap(\.rating)
            let restaurantPhotos = (photosByRestaurant[restaurant.id] ?? []).map(\.1).sorted { left, right in
                if left.kind != right.kind { return left.kind == .restaurantMarker }
                if left.sortOrder != right.sortOrder { return left.sortOrder < right.sortOrder }
                return left.createdAt > right.createdAt
            }
            return RouletteRestaurantRecord(
                restaurantID: restaurant.id,
                globalKey: globalKey(for: restaurant, contract: contract),
                displayName: restaurant.name,
                address: restaurant.address,
                city: restaurant.city,
                status: restaurant.status,
                updatedAt: restaurant.updatedAt,
                deletedAt: restaurant.deletedAt,
                averageRating: ratings.isEmpty ? nil : ratings.reduce(0, +) / Double(ratings.count),
                visitCount: restaurantVisits.count,
                latestVisitAt: restaurantVisits.map(\.visitedAt).max(),
                photoID: restaurantPhotos.first?.id,
                categories: contract?.tags ?? [],
                markerEmoji: contract?.markerEmoji ?? "🍽️",
                latitude: restaurant.latitude,
                longitude: restaurant.longitude
            )
        }
    }

    private static func globalKey(
        for restaurant: Restaurant,
        contract: RestaurantJSONContractV1?
    ) -> String {
        if let primary = contract?.placeIdentities.first(where: \.isPrimary)
            ?? contract?.placeIdentities.first {
            return "\(primary.provider.rawValue):\(primary.externalId)"
        }
        if let appleID = restaurant.appleMapItemIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !appleID.isEmpty {
            return "apple_maps:\(appleID)"
        }
        if let remoteID = restaurant.remoteID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !remoteID.isEmpty {
            return "manual:tastemap:\(remoteID)"
        }
        return "manual:tastemap:\(restaurant.id.uuidString.lowercased())"
    }
}
