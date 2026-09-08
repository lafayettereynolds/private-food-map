import Testing
@testable import TasteMap

struct HybridNativeNavigationPolicyTests {
    @Test func selfNavigatingNativeDestinationsNeverGetASecondHostExit() {
        let ownChrome: Set<TasteMapHybridRouteSurface> = [
            .profileEdit, .restaurantEdit, .restaurantAddToList, .acquisitionNative, .premiumStore,
        ]
        for surface in TasteMapHybridRouteSurface.allCases {
            #expect(TasteMapHybridNativeNavigationPolicy.destinationOwnsNavigation(surface) == ownChrome.contains(surface))
        }
    }
}
