import Foundation
import Observation

@Observable
@MainActor
final class TasteMapHybridNavigationCoordinator {
    private(set) var hybridRoute: TasteMapHybridRouteDTO
    private(set) var presentedNativeRoute: TasteMapHybridRouteDTO?
    private var hybridHistory: [TasteMapHybridRouteDTO]
    var didChange: ((TasteMapHybridNavigationStateDTO) -> Void)?

    init(initialRoute: TasteMapHybridRouteDTO? = nil) {
        // A fresh app session starts at Map. Explicit entry routes still own
        // their destination; foreground resume never constructs this stack.
        let map = try! TasteMapHybridRouteDTO(surface: .map)
        let route = initialRoute?.owner == .hybrid ? initialRoute! : map
        hybridRoute = route
        hybridHistory = [route]
    }

    var current: TasteMapHybridNavigationStateDTO {
        TasteMapHybridNavigationStateDTO(
            route: presentedNativeRoute ?? hybridRoute,
            canGoBack: presentedNativeRoute != nil || hybridHistory.count > 1
        )
    }

    @discardableResult
    func openHybrid(_ route: TasteMapHybridRouteDTO, sourceRequestID: String? = nil, replaceCurrent: Bool = false) throws -> TasteMapHybridNavigationStateDTO {
        guard route.owner == .hybrid else { throw TasteMapHybridRouteError.unsupportedRoute }
        presentedNativeRoute = nil
        if replaceCurrent {
            hybridHistory[hybridHistory.count - 1] = route
            // A completed editor often returns to the Detail directly beneath
            // it. Keep that original Detail entry, not a duplicate return stop.
            if hybridHistory.count > 1 && hybridHistory[hybridHistory.count - 2] == route {
                hybridHistory.removeLast()
            }
        } else if hybridHistory.last != route { hybridHistory.append(route) }
        hybridRoute = route
        return publish(sourceRequestID: sourceRequestID)
    }

    @discardableResult
    func openNative(_ route: TasteMapHybridRouteDTO, sourceRequestID: String? = nil) throws -> TasteMapHybridNavigationStateDTO {
        guard route.owner == .native else { throw TasteMapHybridRouteError.unsupportedRoute }
        presentedNativeRoute = route
        return publish(sourceRequestID: sourceRequestID)
    }

    @discardableResult
    func back(sourceRequestID: String? = nil) -> TasteMapHybridNavigationStateDTO {
        if presentedNativeRoute != nil {
            presentedNativeRoute = nil
        } else if hybridHistory.count > 1 {
            hybridHistory.removeLast()
            hybridRoute = hybridHistory.last!
        }
        return publish(sourceRequestID: sourceRequestID)
    }

    @discardableResult
    func handleExternalRoute(_ route: TasteMapHybridRouteDTO) throws -> TasteMapHybridNavigationStateDTO {
        route.owner == .hybrid ? try openHybrid(route) : try openNative(route)
    }

    func dismissNativePresentation() { _ = back() }

    /// Successful deletion is one Native-owned transition, never two Back calls.
    /// Generic data-change notifications do not determine navigation success.
    @discardableResult
    func completeRestaurantDeletion() -> TasteMapHybridNavigationStateDTO {
        guard presentedNativeRoute?.surface == .restaurantDelete else { return current }
        presentedNativeRoute = nil
        if hybridRoute.surface == .restaurant {
            if hybridHistory.count > 1 {
                hybridHistory.removeLast()
                hybridRoute = hybridHistory.last!
            } else {
                hybridRoute = try! TasteMapHybridRouteDTO(surface: .map)
                hybridHistory = [hybridRoute]
            }
        }
        return publish(completedAction: .restaurantDelete)
    }

    /// Called only after Native commits the final-Visit Restaurant cascade.
    /// Remove proven aliases from retained history without consuming unrelated routes.
    @discardableResult
    func completeVisitDeletion(restaurantIDs: Set<String>, visitIDs: Set<String>) -> TasteMapHybridNavigationStateDTO {
        let restaurants = Set(restaurantIDs.map { $0.lowercased() })
        let visits = Set(visitIDs.map { $0.lowercased() })
        func deletedRoute(_ route: TasteMapHybridRouteDTO) -> Bool {
            guard let id = route.identifier?.lowercased() else { return false }
            switch route.surface {
            case .restaurant, .visit: return restaurants.contains(id)
            case .visitEdit: return visits.contains(id)
            default: return false
            }
        }
        if let presentedNativeRoute, deletedRoute(presentedNativeRoute) { self.presentedNativeRoute = nil }
        hybridHistory.removeAll(where: deletedRoute)
        if hybridHistory.isEmpty { hybridHistory = [try! TasteMapHybridRouteDTO(surface: .map)] }
        hybridRoute = hybridHistory.last!
        return publish(completedAction: .restaurantDelete)
    }

    private func publish(sourceRequestID: String? = nil, completedAction: TasteMapHybridRouteSurface? = nil) -> TasteMapHybridNavigationStateDTO {
        let value = TasteMapHybridNavigationStateDTO(route: current.route, canGoBack: current.canGoBack, sourceRequestID: sourceRequestID, completedAction: completedAction)
        didChange?(value)
        return value
    }
}

enum TasteMapHybridDeepLinkParser {
    static func route(from url: URL) throws -> TasteMapHybridRouteDTO {
        guard url.user == nil, url.password == nil else { throw TasteMapHybridRouteError.malformedURL }
        let scheme = url.scheme?.lowercased()
        guard scheme == "https" || scheme == "tastemap" else { throw TasteMapHybridRouteError.malformedURL }

        let components = url.pathComponents.filter { $0 != "/" }
        let rawSurface: String
        let identifier: String?
        if scheme == "tastemap" {
            rawSurface = url.host?.lowercased() ?? ""
            identifier = components.first
        } else if components.first == "share", components.count == 2 {
            rawSurface = "activity"
            identifier = components[1]
        } else {
            rawSurface = components.first?.lowercased() ?? ""
            identifier = components.dropFirst().first
        }

        let surface: TasteMapHybridRouteSurface
        switch rawSurface {
        case "restaurant": surface = .restaurant
        case "profile": surface = .profile
        case "list", "public-list": surface = .publicList
        case "activity", "share": surface = .activity
        default: throw TasteMapHybridRouteError.unsupportedRoute
        }
        guard let identifier, !identifier.isEmpty else { throw TasteMapHybridRouteError.missingIdentifier }
        return try TasteMapHybridRouteDTO(surface: surface, identifier: identifier.removingPercentEncoding ?? identifier)
    }
}
