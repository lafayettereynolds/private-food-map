import Foundation

/// UI chrome ownership only; it does not change route ownership or permissions.
enum TasteMapHybridNativeNavigationPolicy {
    static func destinationOwnsNavigation(_ surface: TasteMapHybridRouteSurface) -> Bool {
        switch surface {
        case .profileEdit, .restaurantEdit, .restaurantAddToList, .acquisitionNative, .premiumStore:
            true
        default:
            false
        }
    }
}
