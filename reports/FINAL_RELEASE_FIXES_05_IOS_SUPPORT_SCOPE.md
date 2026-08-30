# Taste Map Final Release Fix 05 — iOS Support Scope and Device Family

Date: 2026-08-30
Baseline: `c8cae534e00ad6910abce97df532bfae34e38bfe` (`Restore core Web layout parity`)

## Outcome

Taste Map's first-release support scope is now explicit:

- Minimum OS: **iOS 17.0**
- Device family: **iPhone only** (`UIDeviceFamily = [1]`)
- Supported platforms: `iphoneos` and `iphonesimulator`
- Bundle identifier remains `com.lafayette.tastemap`
- Development Team remains `7G5J9MJX88`
- Signing remains Automatic
- Existing capabilities and entitlements were preserved

The previous iOS 26.5 minimum and universal iPhone/iPad declaration did not describe the actual product support state. The codebase has no dedicated iPad navigation/layout, split-view behavior, landscape acceptance suite, or iPad release screenshots. Declaring iPad support would therefore promise an unverified experience. The release target is intentionally iPhone-only until a separate iPad product and acceptance pass is completed.

## API availability audit

| Framework / feature | Relevant floor | Result |
| --- | ---: | --- |
| SwiftData (`@Model`, `ModelContainer`, `@Query`) | iOS 17 | Sets the architectural floor without a persistence rewrite |
| Observation (`@Observable`) | iOS 17 | Compatible with the selected floor |
| SwiftUI `ContentUnavailableView` and current Map composition APIs | iOS 17 | Compatible with the selected floor |
| StoreKit 2 | iOS 15+ | Does not raise the floor |
| `PhotosPicker`, `ImageRenderer` | iOS 16+ | Does not raise the floor |
| AuthenticationServices / Sign in with Apple | iOS 13+ | Does not raise the floor |
| MapKit `MKMapItem(location:address:)` | iOS 26 | Added an iOS 17–25 `MKPlacemark` fallback |
| MapKit `MKReverseGeocodingRequest`, new address/location APIs | iOS 26 | Added a `CLGeocoder` / placemark fallback |
| MapKit stable `MKMapItem.identifier` | iOS 18 | iOS 17 keeps Taste Map's UUID identity and leaves the optional provider identity absent |

The resulting minimum is not an arbitrary setting change: iOS 17 is the lowest practical target because SwiftData and Observation are core architectural dependencies. Lowering below iOS 17 would require a large persistence/state architecture rewrite and is outside this release-fix scope.

## Compatibility fallbacks

### Apple Maps navigation

- iOS 26+: continues using `MKMapItem(location:address:)`.
- iOS 17–25: creates the same native destination from `MKPlacemark(coordinate:)`.
- Restaurant name and coordinates remain unchanged.

### Restaurant search and location context

- iOS 26+: continues using the current MapKit location/address APIs.
- iOS 17–25: reads coordinates and display addresses from `MKPlacemark` and uses `CLGeocoder` for reverse geocoding.
- iOS 18+: preserves Apple Maps provider identifiers where MapKit exposes them.
- iOS 17: does not fabricate a provider identifier. The stable Taste Map Restaurant UUID remains the global identity, so save and sync remain provider-neutral.

## iPad audit and decision

The repository was checked for dedicated iPad support. No iPad-specific split navigation, adaptive product layout, iPad landscape acceptance tests, or approved iPad screenshot set was found. The existing universal device-family setting was therefore configuration breadth without product verification.

For first release, all app, Share Extension, unit-test, and UI-test targets now consistently declare iPhone family only. This does not delete any iPad-specific implementation because none existed. A future iPad release should be a separate scoped task covering navigation architecture, landscape layouts, keyboard/pointer behavior, UI tests, and App Store screenshots before changing the family back to universal.

## Build, runtime, and signing verification

### Current installed runtime

The Mac currently has iOS Simulator **26.5** only. No iOS 17 simulator runtime is installed.

- Relevant unit regressions on iPhone 17 Pro / iOS 26.5: **passed**
  - Restaurant acquisition and provider-neutral identity
  - Restaurant detail and Apple Maps navigation
  - Map browsing parity
  - Test runtime isolation
- Critical UI paths on iPhone 17 Pro / iOS 26.5: **2 passed**
  - Map/list switch and shared Restaurant Detail
  - Core layout parity evidence
- Debug generic iOS Simulator build: **passed**
- Release generic iOS Simulator build: **passed**
- Debug generic physical iOS device build with existing signing: **passed**

### Minimum-version proof

- The whole app was compiled successfully with deployment target iOS 17.0 after the MapKit fallbacks were added.
- Generated simulator and signed device `TasteMap.app` products report `MinimumOSVersion = 17.0`.
- The embedded Share Extension reports `MinimumOSVersion = 17.0`.
- Generated app and extension products report `UIDeviceFamily = [1]`.

### Signing and capabilities

The signed device product was generated without disabling code signing and without changing signing configuration:

- Application identifier: `7G5J9MJX88.com.lafayette.tastemap`
- Team: `7G5J9MJX88`
- Sign in with Apple: preserved
- Associated domains: preserved
- App group: `group.com.lafayette.tastemap`, preserved
- Automatic signing: preserved

## Remaining release gate

An actual launch/smoke test on the lowest supported iOS 17 runtime could not be executed because this Mac has no iOS 17 simulator runtime installed. This is a **manual release verification item**, not a compile blocker: install an available iOS 17.x Simulator runtime or use an iPhone running iOS 17, then smoke-test launch, map/list, Restaurant Detail, restaurant search, photo selection, Sign in with Apple, and sync.

No claim is made that the iOS 17 runtime smoke test has already passed.

## Files changed

- `ios/TasteMap/TasteMap.xcodeproj/project.pbxproj`
  - deployment target iOS 17.0
  - iPhone-only target family
- `ios/TasteMap/TasteMap/Services/AppleMapsRestaurantNavigator.swift`
  - pre-iOS 26 MapKit fallback
- `ios/TasteMap/TasteMap/Services/RestaurantSearchService.swift`
  - pre-iOS 26 search/geocoding/address fallbacks and iOS 18 provider-ID availability handling
- `ios/TasteMap/TasteMapTests/RestaurantDetailTests.swift`
  - availability-neutral coordinate assertion
- `reports/FINAL_RELEASE_FIXES_05_IOS_SUPPORT_SCOPE.md`

## Safety statement

- No Bundle Identifier change
- No Development Team change
- No signing-mode change
- No capability addition or removal
- No SwiftData schema change
- No Worker, D1, R2, migration, or Production access
- No large old-version rewrite
