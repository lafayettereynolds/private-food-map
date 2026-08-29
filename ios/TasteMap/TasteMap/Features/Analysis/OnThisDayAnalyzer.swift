import Foundation

nonisolated enum OnThisDayAnalyzer {
    static func analyze(
        _ input: OnThisDayInput,
        context: OnThisDayContext
    ) -> OnThisDayReport {
        let calendar = context.calendar
        let reference = calendar.dateComponents([.year, .month, .day], from: context.referenceDate)
        guard let referenceYear = reference.year,
              let referenceMonth = reference.month,
              let referenceDay = reference.day else {
            return OnThisDayReport(
                referenceDate: context.referenceDate, month: 0, day: 0, groups: []
            )
        }

        let restaurantsByID = activeRestaurants(input)
        let dishesByID = activeDishes(input)
        let dishIDsByVisit = activeDishIDsByVisit(input, dishesByID: dishesByID)
        let photos = activePhotos(input)
        let photosByVisit = Dictionary(grouping: photos.compactMap { photo in
            photo.visitID.map { ($0, photo) }
        }, by: \.0).mapValues { $0.map(\.1) }
        let photosByDish = Dictionary(grouping: photos.compactMap { photo in
            photo.dishID.map { ($0, photo) }
        }, by: \.0).mapValues { $0.map(\.1) }
        let markerPhotosByRestaurant = Dictionary(grouping: photos.filter {
            $0.kind == .restaurantMarker && $0.restaurantID != nil
        }, by: { $0.restaurantID! })

        var memories = [OnThisDayMemory]()
        memories.reserveCapacity(8)
        for visit in input.visits {
            guard visit.deletedAt == nil,
                  OnThisDayInput.isOwned(visit.ownerUserID, by: input.currentUserID),
                  let restaurant = restaurantsByID[visit.restaurantID],
                  OnThisDayInput.isOwned(restaurant.ownerUserID, by: input.currentUserID) else { continue }
            let components = calendar.dateComponents([.year, .month, .day], from: visit.visitedAt)
            guard let year = components.year,
                  year < referenceYear,
                  components.month == referenceMonth,
                  components.day == referenceDay else { continue }

            let dishIDs = dishIDsByVisit[visit.id] ?? []
            let dishNames = dishIDs.compactMap { dishesByID[$0] }.sorted(by: dishSort).map(\.name)
            var photoCandidates = photosByVisit[visit.id] ?? []
            for dishID in dishIDs { photoCandidates += photosByDish[dishID] ?? [] }
            photoCandidates += markerPhotosByRestaurant[visit.restaurantID] ?? []
            let imageReference = photoCandidates.sorted {
                photoSort($0, $1, visitID: visit.id, dishIDs: dishIDs)
            }.first.map { AnalysisImageReference.photo($0.id) } ?? .none

            memories.append(OnThisDayMemory(
                id: visit.id,
                restaurantID: visit.restaurantID,
                year: year,
                yearsAgo: referenceYear - year,
                visitedAt: visit.visitedAt,
                restaurantName: restaurant.name.onThisDayDisplayValue ?? "未命名餐厅",
                city: restaurant.city.onThisDayDisplayValue ?? "",
                rating: visit.rating,
                note: visit.note?.onThisDayDisplayValue,
                spend: validSpend(visit.myActualSpend),
                companions: visit.companionNames.compactMap(\.onThisDayDisplayValue),
                recommendationSource: visit.recommendationSource?.onThisDayDisplayValue,
                dishNames: dishNames,
                imageReference: imageReference
            ))
        }

        memories.sort(by: memorySort)
        let groups = Dictionary(grouping: memories, by: \.year).map { year, values in
            OnThisDayYearGroup(year: year, memories: values.sorted(by: memorySort))
        }.sorted { $0.year > $1.year }
        return OnThisDayReport(
            referenceDate: context.referenceDate,
            month: referenceMonth,
            day: referenceDay,
            groups: groups
        )
    }

    private static func activeRestaurants(
        _ input: OnThisDayInput
    ) -> [UUID: OnThisDayInput.RestaurantRecord] {
        input.restaurants.filter {
            $0.deletedAt == nil && OnThisDayInput.isOwned($0.ownerUserID, by: input.currentUserID)
        }.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }.reduce(into: [:]) { result, restaurant in
            if result[restaurant.id] == nil { result[restaurant.id] = restaurant }
        }
    }

    private static func activeDishes(
        _ input: OnThisDayInput
    ) -> [UUID: OnThisDayInput.DishRecord] {
        input.dishes.filter { $0.deletedAt == nil }.sorted(by: dishSort).reduce(into: [:]) {
            if $0[$1.id] == nil { $0[$1.id] = $1 }
        }
    }

    private static func activeDishIDsByVisit(
        _ input: OnThisDayInput,
        dishesByID: [UUID: OnThisDayInput.DishRecord]
    ) -> [UUID: [UUID]] {
        input.visitDishes.filter {
            $0.deletedAt == nil && dishesByID[$0.dishID] != nil
        }.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            if $0.dishID != $1.dishID { return $0.dishID.uuidString < $1.dishID.uuidString }
            return $0.visitID.uuidString < $1.visitID.uuidString
        }.reduce(into: [:]) { result, link in
            if result[link.visitID, default: []].contains(link.dishID) == false {
                result[link.visitID, default: []].append(link.dishID)
            }
        }
    }

    private static func activePhotos(_ input: OnThisDayInput) -> [OnThisDayInput.PhotoRecord] {
        input.photos.filter { $0.deletedAt == nil && $0.binaryDeletedAt == nil }
    }

    private static func memorySort(_ lhs: OnThisDayMemory, _ rhs: OnThisDayMemory) -> Bool {
        if lhs.year != rhs.year { return lhs.year > rhs.year }
        if lhs.visitedAt != rhs.visitedAt { return lhs.visitedAt > rhs.visitedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func dishSort(
        _ lhs: OnThisDayInput.DishRecord,
        _ rhs: OnThisDayInput.DishRecord
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func photoSort(
        _ lhs: OnThisDayInput.PhotoRecord,
        _ rhs: OnThisDayInput.PhotoRecord,
        visitID: UUID,
        dishIDs: [UUID]
    ) -> Bool {
        let dishIDSet = Set(dishIDs)
        func rank(_ photo: OnThisDayInput.PhotoRecord) -> Int {
            if photo.kind == .visit && photo.visitID == visitID { return 0 }
            if photo.kind == .dish && photo.dishID.map(dishIDSet.contains) == true { return 1 }
            if photo.kind == .restaurantMarker { return 2 }
            return 3
        }
        let lhsRank = rank(lhs), rhsRank = rank(rhs)
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func validSpend(_ spend: Decimal?) -> Decimal? {
        guard let spend, spend >= 0 else { return nil }
        return spend
    }
}

private extension String {
    nonisolated var onThisDayDisplayValue: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
