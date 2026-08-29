import Foundation

struct DishReuseUsage: Equatable, Sendable {
    let count: Int
    let lastUsedAt: Date?
}

@MainActor
enum DishReuseResolver {
    static func usage(
        restaurantID: UUID,
        dishes: [Dish],
        associations: [VisitDish],
        visits: [Visit]
    ) -> [UUID: DishReuseUsage] {
        let activeVisitPairs: [(UUID, Visit)] = visits.compactMap { visit in
            guard visit.restaurantId == restaurantID, visit.deletedAt == nil else { return nil }
            return (visit.id, visit)
        }
        let activeVisitByID = Dictionary(uniqueKeysWithValues: activeVisitPairs)
        let activeDishIDs = Set(dishes.filter {
            $0.restaurantId == restaurantID && $0.deletedAt == nil
        }.map(\.id))
        var visitIDsByDish: [UUID: Set<UUID>] = [:]
        for association in associations where
            association.restaurantId == restaurantID && association.deletedAt == nil &&
            activeDishIDs.contains(association.dishId) && activeVisitByID[association.visitId] != nil {
            visitIDsByDish[association.dishId, default: []].insert(association.visitId)
        }
        return Dictionary(uniqueKeysWithValues: activeDishIDs.map { dishID in
            let visitIDs = visitIDsByDish[dishID] ?? []
            let latest = visitIDs.compactMap { activeVisitByID[$0]?.visitedAt }.max()
            return (dishID, DishReuseUsage(count: visitIDs.count, lastUsedAt: latest))
        })
    }

    static func orderedUniqueDishes(
        restaurantID: UUID,
        dishes: [Dish],
        usageByDishID: [UUID: DishReuseUsage]
    ) -> [Dish] {
        var seen = Set<String>()
        return dishes
            .filter { $0.restaurantId == restaurantID && $0.deletedAt == nil }
            .sorted { left, right in
                let leftUsage = usageByDishID[left.id] ?? .init(count: 0, lastUsedAt: nil)
                let rightUsage = usageByDishID[right.id] ?? .init(count: 0, lastUsedAt: nil)
                if leftUsage.count != rightUsage.count { return leftUsage.count > rightUsage.count }
                if leftUsage.lastUsedAt != rightUsage.lastUsedAt {
                    return (leftUsage.lastUsedAt ?? .distantPast) > (rightUsage.lastUsedAt ?? .distantPast)
                }
                if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
            .filter { seen.insert(DishIdentity.normalizedName($0.name)).inserted }
    }
}
