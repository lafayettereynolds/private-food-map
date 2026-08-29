import Foundation

enum RestaurantBrowseSegment: String, CaseIterable, Identifiable {
    case visited
    case wantToGo
    case forYou

    var id: Self { self }

    var title: String {
        switch self {
        case .visited: "去过"
        case .wantToGo: "想吃"
        case .forYou: "适合你"
        }
    }

    var systemImage: String {
        switch self {
        case .visited: "fork.knife.circle"
        case .wantToGo: "bookmark.circle"
        case .forYou: "sparkles"
        }
    }

    var emptyTitle: String {
        switch self {
        case .visited: "还没有去过的餐厅"
        case .wantToGo: "还没有想吃的餐厅"
        case .forYou: "暂无适合你的本地结果"
        }
    }

    var emptyMessage: String {
        switch self {
        case .visited: "搜索一家真实餐厅，保存第一次到访后就会出现在这里。"
        case .wantToGo: "搜索一家真实餐厅，把它加入你的想吃清单。"
        case .forYou: "个性推荐仍由现有发现能力提供，这里不会生成虚构内容。"
        }
    }
}

struct RestaurantBrowseItem: Identifiable {
    let restaurant: Restaurant
    let visitCount: Int
    let latestVisitAt: Date?
    let averageRating: Double?
    let photo: PhotoAsset?
    let visitFacets: [PersonalVisitFilterFacet]
    let normalizedSearchText: String

    var id: UUID { restaurant.id }
}

struct TasteFootprintItem: Identifiable {
    let visit: Visit
    let restaurant: Restaurant
    let photo: PhotoAsset?
    let dishNames: [String]
    let companionNames: [String]
    let recommendationSource: String?

    var id: UUID { visit.id }
}

struct RestaurantBrowseSnapshot {
    let visited: [RestaurantBrowseItem]
    let wantToGo: [RestaurantBrowseItem]
    let footprints: [TasteFootprintItem]
    let filterOptions: PersonalRestaurantFilterOptions

    func items(for segment: RestaurantBrowseSegment) -> [RestaurantBrowseItem] {
        switch segment {
        case .visited: visited
        case .wantToGo: wantToGo
        case .forYou: []
        }
    }
}

@MainActor
enum RestaurantBrowseBuilder {
    static func build(
        restaurants: [Restaurant],
        visits: [Visit],
        photos: [PhotoAsset] = [],
        dishes: [Dish] = [],
        visitDishes: [VisitDish] = [],
        companions: [DiningCompanion] = [],
        recommendationSources: [RecommendationSource] = []
    ) -> RestaurantBrowseSnapshot {
        let activeRestaurants = restaurants.filter { $0.deletedAt == nil }
        let restaurantByID = Dictionary(uniqueKeysWithValues: activeRestaurants.map { ($0.id, $0) })
        let activeVisits = visits.filter {
            $0.deletedAt == nil && restaurantByID[$0.restaurantId] != nil
        }
        let activeVisitIDs = Set(activeVisits.map(\.id))
        let visitsByRestaurant = Dictionary(grouping: activeVisits, by: \.restaurantId)

        let activePhotos = photos.filter {
            $0.deletedAt == nil
                && $0.binaryDeletedAt == nil
                && ($0.visitId.map(activeVisitIDs.contains) ?? true)
        }
        let photosByRestaurant = Dictionary(grouping: activePhotos.compactMap { photo in
            photo.restaurantId.map { ($0, photo) }
        }, by: \.0)
        let photosByVisit = Dictionary(grouping: activePhotos.compactMap { photo in
            photo.visitId.map { ($0, photo) }
        }, by: \.0)

        let activeDishes = dishes.filter { $0.deletedAt == nil && restaurantByID[$0.restaurantId] != nil }
        let dishByID = Dictionary(uniqueKeysWithValues: activeDishes.map { ($0.id, $0) })
        var dishesByVisit: [UUID: [Dish]] = [:]
        var associatedDishIDs: Set<UUID> = []
        for association in visitDishes where association.deletedAt == nil {
            guard restaurantByID[association.restaurantId] != nil,
                  let dish = dishByID[association.dishId],
                  activeVisitIDs.contains(association.visitId) else { continue }
            dishesByVisit[association.visitId, default: []].append(dish)
            associatedDishIDs.insert(dish.id)
        }
        for dish in activeDishes where !associatedDishIDs.contains(dish.id) {
            dishesByVisit[dish.visitId, default: []].append(dish)
        }

        let companionNamesByID = directoryNames(companions)
        let sourceNamesByID = directoryNames(recommendationSources)

        let visited = activeRestaurants
            .filter { $0.status == .visited }
            .map { restaurant in
                browseItem(
                    restaurant: restaurant,
                    visits: visitsByRestaurant[restaurant.id] ?? [],
                    photos: (photosByRestaurant[restaurant.id] ?? []).map(\.1),
                    dishesByVisit: dishesByVisit,
                    companionDirectory: companionNamesByID,
                    sourceDirectory: sourceNamesByID,
                    preferMarker: false
                )
            }
            .sorted(by: visitedOrder)

        let wantToGo = activeRestaurants
            .filter { $0.status == .wantToGo }
            .map { restaurant in
                browseItem(
                    restaurant: restaurant,
                    visits: visitsByRestaurant[restaurant.id] ?? [],
                    photos: (photosByRestaurant[restaurant.id] ?? []).map(\.1),
                    dishesByVisit: dishesByVisit,
                    companionDirectory: companionNamesByID,
                    sourceDirectory: sourceNamesByID,
                    preferMarker: true
                )
            }
            .sorted(by: wantToGoOrder)

        let footprints = activeVisits
            .sorted(by: visitOrder)
            .compactMap { visit -> TasteFootprintItem? in
                guard let restaurant = restaurantByID[visit.restaurantId] else { return nil }
                let photo = preferredPhoto(
                    from: (photosByVisit[visit.id] ?? []).map(\.1),
                    preferMarker: false
                )
                let names = (dishesByVisit[visit.id] ?? [])
                    .sorted { left, right in
                        left.sortOrder == right.sortOrder
                            ? left.name.localizedStandardCompare(right.name) == .orderedAscending
                            : left.sortOrder < right.sortOrder
                    }
                    .map(\.name)
                return TasteFootprintItem(
                    visit: visit,
                    restaurant: restaurant,
                    photo: photo,
                    dishNames: stableNames(names),
                    companionNames: companionNames(for: visit, directory: companionNamesByID),
                    recommendationSource: sourceName(for: visit, directory: sourceNamesByID)
                )
            }

        let browseItems = visited + wantToGo
        return RestaurantBrowseSnapshot(
            visited: visited,
            wantToGo: wantToGo,
            footprints: footprints,
            filterOptions: PersonalRestaurantFilterProjection.options(from: browseItems)
        )
    }

    private static func browseItem(
        restaurant: Restaurant,
        visits: [Visit],
        photos: [PhotoAsset],
        dishesByVisit: [UUID: [Dish]],
        companionDirectory: [String: String],
        sourceDirectory: [String: String],
        preferMarker: Bool
    ) -> RestaurantBrowseItem {
        let ratings = visits.compactMap(\.rating)
        let restaurantRecord = restaurant.remoteRecordData.flatMap {
            try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0)
        }
        let searchTerms = [
            restaurant.name,
            restaurant.city,
            restaurant.address,
            restaurantRecord?.longTermNote ?? "",
        ] + visits.flatMap { visit in
            let dishes = dishesByVisit[visit.id] ?? []
            return [visit.note ?? ""]
                + companionNames(for: visit, directory: companionDirectory)
                + dishes.flatMap { [$0.name, $0.taste] }
        }
        return RestaurantBrowseItem(
            restaurant: restaurant,
            visitCount: visits.count,
            latestVisitAt: visits.map(\.visitedAt).max(),
            averageRating: ratings.isEmpty ? nil : ratings.reduce(0, +) / Double(ratings.count),
            photo: preferredPhoto(from: photos, preferMarker: preferMarker),
            visitFacets: visits.map {
                filterFacet(
                    for: $0,
                    companionDirectory: companionDirectory,
                    sourceDirectory: sourceDirectory
                )
            },
            normalizedSearchText: RestaurantBrowseSearch.normalized(searchTerms.joined(separator: "\n"))
        )
    }

    private static func filterFacet(
        for visit: Visit,
        companionDirectory: [String: String],
        sourceDirectory: [String: String]
    ) -> PersonalVisitFilterFacet {
        let companionOptions = Set(companionNames(for: visit, directory: companionDirectory).map {
            PersonalFilterOption(
                id: PersonalRestaurantFilterProjection.optionID(prefix: "companion", title: $0),
                title: $0
            )
        })
        var sourceTitles: [String] = []
        if let sourceID = visit.recommendationSourceID,
           let directoryName = sourceDirectory[sourceID], !directoryName.isEmpty {
            sourceTitles.append(directoryName)
        }
        if let sourceText = visit.recommendationSourceText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceText.isEmpty {
            sourceTitles.append(sourceText)
        }
        if let sourceType = visit.recommendationSourceType {
            sourceTitles.append(sourceType.title)
        }
        let sourceOptions = Set(stableNames(sourceTitles).map {
            PersonalFilterOption(
                id: PersonalRestaurantFilterProjection.optionID(prefix: "source", title: $0),
                title: $0
            )
        })
        return PersonalVisitFilterFacet(
            visitedAt: visit.visitedAt,
            rating: visit.rating,
            pricePerPerson: visit.pricePerPerson.map { NSDecimalNumber(decimal: $0).doubleValue },
            diningMode: visit.diningMode,
            queueDuration: visit.queueDuration,
            occasionRawValues: Set(visit.diningOccasionRawValues),
            companionOptions: companionOptions,
            sourceOptions: sourceOptions
        )
    }

    private static func preferredPhoto(
        from photos: [PhotoAsset],
        preferMarker: Bool
    ) -> PhotoAsset? {
        photos.min { left, right in
            if preferMarker, left.kind != right.kind {
                return left.kind == .restaurantMarker
            }
            if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
            if left.sortOrder != right.sortOrder { return left.sortOrder < right.sortOrder }
            return left.id.uuidString < right.id.uuidString
        }
    }

    private static func visitedOrder(_ left: RestaurantBrowseItem, _ right: RestaurantBrowseItem) -> Bool {
        let leftDate = left.latestVisitAt ?? left.restaurant.createdAt
        let rightDate = right.latestVisitAt ?? right.restaurant.createdAt
        if leftDate != rightDate { return leftDate > rightDate }
        return stableRestaurantOrder(left, right)
    }

    private static func wantToGoOrder(_ left: RestaurantBrowseItem, _ right: RestaurantBrowseItem) -> Bool {
        if left.restaurant.createdAt != right.restaurant.createdAt {
            return left.restaurant.createdAt > right.restaurant.createdAt
        }
        return stableRestaurantOrder(left, right)
    }

    private static func stableRestaurantOrder(_ left: RestaurantBrowseItem, _ right: RestaurantBrowseItem) -> Bool {
        let comparison = left.restaurant.name.localizedStandardCompare(right.restaurant.name)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return left.id.uuidString < right.id.uuidString
    }

    private static func visitOrder(_ left: Visit, _ right: Visit) -> Bool {
        if left.visitedAt != right.visitedAt { return left.visitedAt > right.visitedAt }
        return left.id.uuidString < right.id.uuidString
    }

    private static func directoryNames<T>(_ values: [T]) -> [String: String] {
        var result: [String: String] = [:]
        for value in values {
            if let companion = value as? DiningCompanion, companion.deletedAt == nil {
                result[companion.id.uuidString.lowercased()] = companion.displayName
                if let remoteID = companion.remoteID { result[remoteID] = companion.displayName }
            } else if let source = value as? RecommendationSource, source.deletedAt == nil {
                result[source.id.uuidString.lowercased()] = source.displayName
                if let remoteID = source.remoteID { result[remoteID] = source.displayName }
            }
        }
        return result
    }

    private static func companionNames(for visit: Visit, directory: [String: String]) -> [String] {
        stableNames(visit.companionNames + visit.companionIDs.compactMap { directory[$0] })
    }

    private static func sourceName(for visit: Visit, directory: [String: String]) -> String? {
        if let id = visit.recommendationSourceID, let name = directory[id], !name.isEmpty { return name }
        if let text = visit.recommendationSourceText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty { return text }
        return visit.recommendationSourceType?.title
    }

    private static func stableNames(_ values: [String]) -> [String] {
        var keys: Set<String> = []
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return keys.insert(key).inserted ? trimmed : nil
        }
    }
}

enum RestaurantBrowseSearch {
    static func filter(_ items: [RestaurantBrowseItem], query: String) -> [RestaurantBrowseItem] {
        let query = normalized(query)
        guard !query.isEmpty else { return items }
        return items.filter { $0.normalizedSearchText.contains(query) }
    }

    static func normalized(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
