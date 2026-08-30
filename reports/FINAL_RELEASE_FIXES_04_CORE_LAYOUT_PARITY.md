# Taste Map Final Release Fixes — Task 04

## Core Map, List, and Restaurant Detail Layout Parity

- Date: 2026-08-30
- Branch: `main`
- Baseline: `61321e6dac359b2e67639792d631b70ae1c1b8e2`
- Intended commit: `Restore core Web layout parity`
- Scope: native iOS layout and presentation only
- Web/Worker/D1/Production changes: none

## Outcome

Task 04 is complete. The native iOS map, personal restaurant list, and restaurant detail first screen now follow the hierarchy demonstrated by the approved Web references without copying browser chrome or changing business behavior.

The map now owns the first screen instead of beginning below a large navigation title and multiple stacked toolbars. The list uses compact information rows rather than large cards. Restaurant detail begins with a real hero area, followed by restaurant identity, rating and sample count, core actions, and compact supporting content.

## Source-of-truth evidence

Web references copied into this task's immutable evidence folder:

- [Web map reference](final-release-fixes-04-assets/web-map-reference.png)
- [Web list reference](final-release-fixes-04-assets/web-list-reference.png)
- [Web restaurant detail reference](final-release-fixes-04-assets/web-restaurant-detail-reference.jpg)

The original audit asset folder was not staged, edited, moved, or deleted.

## Before and after

### Map

- [iOS map before](final-release-fixes-04-assets/ios-map-before.png)
- [iOS map after — iPhone 17 Pro](final-release-fixes-04-assets/ios-map-after-iphone-17-pro.png)
- [iOS map after — iPhone 17e](final-release-fixes-04-assets/ios-map-after-iphone-17e.png)
- [iOS map after — dark appearance](final-release-fixes-04-assets/ios-map-after-dark.png)

Changes:

- Removed the large `Taste Map` navigation-title layer from map/list browsing.
- Moved `去过 / 想吃 / 适合你` into one compact floating control.
- Replaced the second full-width segmented header with compact map/list icon controls.
- Integrated list search and filter/sort into the same compact control plane.
- Allowed MapKit to extend through the top and bottom safe-area backgrounds.
- Retained visible separation between marker content, `+ 添加餐厅`, and the bottom app navigation.
- Moved denied-location, loading, empty, and error states below the compact controls so they remain readable without blocking launch.

Measured UI assertions:

- Map render height is greater than 72% of the full application frame.
- The primary and map/list control stack is at most 112 points tall.
- The map/list control bottom remains within 170 points of the map's top edge.
- The add-restaurant CTA remains above the bottom `地图` tab and is hittable.

### Personal restaurant list

- [iOS list after — iPhone 17 Pro](final-release-fixes-04-assets/ios-list-after-iphone-17-pro.png)
- [iOS list after — iPhone 17e](final-release-fixes-04-assets/ios-list-after-iphone-17e.png)

Changes:

- Removed per-row card shadows and rounded card containers.
- Reduced restaurant artwork from 92×92 to 52×52 points.
- Reordered row hierarchy to name, visit/rating summary, then compact location.
- Replaced large inter-card gaps with native dividers and 14-point section insets.
- Kept long restaurant names readable over two lines.
- Preserved real visit counts, optional ratings, photos/fallbacks, search, filter, sort, and detail navigation.

Measured UI assertions:

- Long-name fixture row is no more than 96 points tall.
- Row leading inset is 14 points.
- Inline list search remains present and accessible on both tested phone sizes.

### Restaurant detail

- [iOS detail after — iPhone 17 Pro](final-release-fixes-04-assets/ios-detail-after-iphone-17-pro.png)
- [iOS detail after — iPhone 17e](final-release-fixes-04-assets/ios-detail-after-iphone-17e.png)

New first-screen order:

1. 216-point restaurant hero or honest no-photo fallback
2. City, restaurant name, address, and status
3. Rating reference with large rating circle and small sample-count circle
4. Three primary actions
5. Compact secondary actions
6. Compact business information, personal statistics, dishes, detailed ratings, location, and visit history

The former six-action grid is replaced by three visually primary actions (`记录到访`, want-to-go state, and roulette), followed by one compact row for edit, list, sharing, and a More menu. Copy and destructive deletion remain available in More. The existing toolbar edit/delete routes and confirmation flow remain intact.

Measured UI assertions:

- Hero appears before restaurant identity.
- Core actions remain within a 190-point presentation area.
- The bottom visit CTA remains separate from scroll content and usable on both tested sizes.

## Rating visual contract

The approved visual meaning is preserved explicitly:

- Large circle: rating value.
- Small overlaid circle: sample count.

Nil ratings are still excluded by the existing presentation model. No rating algorithm or data semantics changed.

## Functional preservation

The following existing behavior was regression-tested after the layout changes:

- Map/list switching and shared restaurant detail navigation.
- Multi-select personal filtering, apply, list parity, and reset.
- Restaurant metadata display and editing.
- Visit creation from restaurant detail and refreshed visit statistics.
- Record visit, want-to-go, list, roulette, public-share eligibility, copy, and delete actions.
- Confirmed restaurant deletion and tombstone behavior.
- Apple Maps-only restaurant behavior and provider identity preservation.
- Restaurant owner isolation and mutation authorization.

No schema, model, API contract, sync policy, auth credential flow, Worker route, D1 migration, or Production configuration was changed.

## Isolated test-runtime correction

Task 04 regression testing exposed one test-only state omission from the already-completed runtime-isolation work: automatic services are deliberately disabled in UI/unit runtimes, but the local account scope could remain indefinitely in `restoring`. That made fixture mutation controls appear in the accessibility tree while remaining disabled.

`TasteMapApp` now resolves isolated runtimes with no persisted credential to the explicit local signed-out workspace by reusing the existing `endLocalAccountSession()` method. This does not read the real Keychain, contact an endpoint, change Apple authentication, or alter normal application behavior. Production runtime behavior remains unchanged and the existing fail-closed network isolation tests still pass.

## Test results

### Relevant unit tests

Command selected the seven relevant suites:

- `MapBrowsingParityTests`
- `F2AMapListFootprintsTests`
- `F2BPersonalRestaurantFilterTests`
- `RestaurantDetailTests`
- `RestaurantDetailCompletionTests`
- `RestaurantModuleParityTests`
- `TestRuntimeIsolationTests`

Result: **78 tests in 7 suites passed**.

### UI regression and evidence tests

Passed on iPhone 17 Pro:

- `testF2AMapListSwitchAndSharedRestaurantDetail`
- `testF2BMapFilterMultiSelectApplyListParityAndReset`
- `testF3ARestaurantDetailMetadataEditAndVisitRefresh`
- `testRestaurantParityActionsShareHookAndConfirmedDelete`
- `testTask04CoreLayoutParityEvidence`
- `testTask04DarkLayoutKeepsCompactMapControls`

Passed on iPhone 17e:

- `testTask04CoreLayoutParityEvidence`

The small-device run used an explicit Simulator location grant only to avoid an unrelated first-launch system alert interrupting screenshot capture. Location-denied behavior remains covered by the existing non-blocking map behavior and was not changed.

### Builds

- iOS Debug, generic iOS Simulator: **passed**.
- iOS Release, generic iOS Simulator: **passed**.
- Code signing was disabled only for Simulator validation.

## Files changed

- `ios/TasteMap/TasteMap/Features/Map/MapHomeView.swift`
- `ios/TasteMap/TasteMap/Features/Map/RestaurantBrowseViews.swift`
- `ios/TasteMap/TasteMap/Features/Restaurant/RestaurantDetailComponents.swift`
- `ios/TasteMap/TasteMap/Features/Restaurant/RestaurantDetailView.swift`
- `ios/TasteMap/TasteMap/Features/Restaurant/RestaurantQuickActionsSection.swift`
- `ios/TasteMap/TasteMap/TasteMapApp.swift`
- `ios/TasteMap/TasteMapUITests/TasteMapUITests.swift`
- `reports/FINAL_RELEASE_FIXES_04_CORE_LAYOUT_PARITY.md`
- `reports/final-release-fixes-04-assets/*`

## Safety statement

- Bundle Identifier: unchanged.
- Apple Developer Team and signing: unchanged.
- Capabilities: unchanged.
- App Icon: unchanged.
- SwiftData schema: unchanged.
- Worker/D1/migrations: unchanged.
- Production: not accessed.
- Existing user `project.pbxproj` modification: preserved and excluded from this task commit.
- Existing stash and unrelated untracked files: preserved and excluded.

## Acceptance

Task 04 satisfies the ZIP specification and is ready for the required independent commit and push. After the push is verified with `HEAD == origin/main`, serial execution may continue with Task 05.
