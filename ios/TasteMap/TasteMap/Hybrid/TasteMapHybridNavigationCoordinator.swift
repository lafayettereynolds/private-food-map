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
        let profile = try! TasteMapHybridRouteDTO(surface: .profile)
        let route = initialRoute?.owner == .hybrid ? initialRoute! : profile
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
    func openHybrid(_ route: TasteMapHybridRouteDTO) throws -> TasteMapHybridNavigationStateDTO {
        guard route.owner == .hybrid else { throw TasteMapHybridRouteError.unsupportedRoute }
        presentedNativeRoute = nil
        if hybridHistory.last != route { hybridHistory.append(route) }
        hybridRoute = route
        return publish()
    }

    @discardableResult
    func openNative(_ route: TasteMapHybridRouteDTO) throws -> TasteMapHybridNavigationStateDTO {
        guard route.owner == .native else { throw TasteMapHybridRouteError.unsupportedRoute }
        presentedNativeRoute = route
        return publish()
    }

    @discardableResult
    func back() -> TasteMapHybridNavigationStateDTO {
        if presentedNativeRoute != nil {
            presentedNativeRoute = nil
        } else if hybridHistory.count > 1 {
            hybridHistory.removeLast()
            hybridRoute = hybridHistory.last!
        }
        return publish()
    }

    @discardableResult
    func handleExternalRoute(_ route: TasteMapHybridRouteDTO) throws -> TasteMapHybridNavigationStateDTO {
        route.owner == .hybrid ? try openHybrid(route) : try openNative(route)
    }

    func dismissNativePresentation() { _ = back() }

    private func publish() -> TasteMapHybridNavigationStateDTO {
        let value = current
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
