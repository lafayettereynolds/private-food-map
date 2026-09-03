import Observation
import SwiftUI

@Observable
final class RestaurantRouletteSession {
    private(set) var restaurantIDs: [UUID] = []
    private(set) var hasExplicitSelection = false

    var shouldShowMapDock: Bool {
        hasExplicitSelection && !restaurantIDs.isEmpty
    }

    func contains(_ restaurantID: UUID) -> Bool {
        restaurantIDs.contains(restaurantID)
    }

    @discardableResult
    func toggle(_ restaurantID: UUID) -> Bool {
        hasExplicitSelection = true
        if let index = restaurantIDs.firstIndex(of: restaurantID) {
            restaurantIDs.remove(at: index)
            return true
        }
        guard restaurantIDs.count < RestaurantRouletteEngine.maximumActiveCandidateCount else {
            return false
        }
        restaurantIDs.append(restaurantID)
        return true
    }

    func replace(with restaurantIDs: [UUID]) {
        hasExplicitSelection = true
        var seen = Set<UUID>()
        self.restaurantIDs = restaurantIDs.filter { seen.insert($0).inserted }
            .prefix(RestaurantRouletteEngine.maximumActiveCandidateCount)
            .map { $0 }
    }

    func clear() {
        hasExplicitSelection = true
        restaurantIDs.removeAll()
    }
}

private struct RestaurantRouletteSessionEnvironmentKey: EnvironmentKey {
    static let defaultValue: RestaurantRouletteSession? = nil
}

extension EnvironmentValues {
    var restaurantRouletteSession: RestaurantRouletteSession? {
        get { self[RestaurantRouletteSessionEnvironmentKey.self] }
        set { self[RestaurantRouletteSessionEnvironmentKey.self] = newValue }
    }
}
