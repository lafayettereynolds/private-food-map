# Add Restaurant + GPS / Nearby parity report

## Scope and baseline

- Worktree: `/Users/lafayette/Projects/private-food-map-nearby`
- Branch: `fix/add-restaurant-nearby-parity`
- Baseline: `origin/main` at `2b7ffa8c8ac6d7c83099c3f45a4eed16bee0d620`
- Product source of truth: `src/components/AddRestaurantModal.tsx` plus the Web map/acquisition services it calls.
- Production was not opened, changed, or deployed. The Web app was started locally from this worktree. The in-app browser could not render localhost because its admin policy check was unavailable; source, live local server startup, TypeScript tests, and the complete event/data path were used for verification without bypassing that control.

## Web source-of-truth flow

### Entry order, initial state, and page structure

1. The global bottom-navigation Add Restaurant action opens the large `AddRestaurantModal` with the title “添加餐厅”.
2. The first visible acquisition block is the restaurant-name search, with city beside it. The city starts from `private-food-map-last-city` when available.
3. The inline link/share-text importer follows search. It accepts AMap, Apple Maps, ordinary HTTPS restaurant URLs, and share text.
4. Before an explicit keyword search, the Nearby Restaurants block follows the link importer.
5. Search hints/results follow Nearby; the last acquisition entry is “地图上搜不到？手动添加”.
6. Selecting a new candidate moves to “写下这家餐厅”. It defaults to Visited, but the user can switch to WantToGo before saving. An already-known POI bypasses duplicate creation and opens Record Visit.

### Automatic GPS and Nearby

- Opening the page automatically starts GPS and Nearby when AMap is configured; the user does not press a locate button first.
- Browser geolocation uses `enableHighAccuracy: true`, `maximumAge: 0`, and an 8-second timeout. A result with accuracy worse than 1,000 m is rejected as coarse rather than presented as precise.
- WGS-84 browser GPS is converted to the AMap coordinate system. That converted GPS coordinate is the one and only center supplied to both the 3 km Nearby query and reverse geocoding.
- Nearby and reverse geocoding run together after the GPS fix. A 12-second page watchdog leaves an honest timeout message and never substitutes city-center results.
- The reverse-geocoded address is shown under the city field as “已定位：…”. Detected city updates the stored/default city only when the user has not edited it during location.
- Nearby merges the `餐厅`, `美食`, and `饭店` category searches, deduplicates by AMap POI ID, computes distance from the same GPS center, sorts nearest first, and shows up to eight results. The search region only constrains provider candidates; it is not the distance origin.

### Search and city switching

- The user enters a restaurant name/address and may edit the city directly.
- Submitting a non-empty search hides Nearby and shows the explicit search result/loading/error/empty state.
- Search uses the selected city and, when current GPS exists, a 20 km center/radius hint. Clearing the keyword clears the explicit-search state and restores Nearby.
- A missing map configuration disables search and displays configuration guidance; it does not manufacture results.

### Link/share-text acquisition

- The importer is inline and remains ahead of Nearby.
- Apple Maps, AMap, ordinary HTTPS URLs, and mixed share text are parsed/resolved into candidates for explicit confirmation.
- When a link resolver cannot identify one store but returns a fallback keyword, the Web flow fills keyword/city, performs a normal restaurant search, and uses a link coordinate when provided or current GPS otherwise.
- An unrecognized/failed link leaves search and manual acquisition available.

### Candidate, WantToGo, Visited, and dedupe behavior

- New search/Nearby/link candidates show “选择”; selection opens the second step rather than writing immediately.
- The second step defaults to Visited. It includes the restaurant summary, editable address, Visited/WantToGo choice, and display settings.
- Visited exposes the visit record fields (rating, note, spend, date/time, party, companions, queue, photos, dishes, and detail fields) and creates an initial visit only on final save.
- WantToGo removes the visit form, accepts an optional expected price, and saves without an initial visit.
- A candidate whose AMap POI ID already exists shows “再次记录到访” and opens the existing restaurant’s visit flow. The database also rejects an active duplicate with the same AMap POI ID.

### Manual and no-result degradation

- Manual add is the final acquisition entry. It collects name, city, and address/landmark, can request current GPS, or geocodes the entered address.
- After position confirmation it produces a deterministic manual candidate and continues through the same Visited/WantToGo detail step.
- GPS denied/failed, Nearby empty, search empty, link unresolved, and map-missing states all keep city search/link/manual alternatives visible. None silently substitutes a city, camera, prior restaurant, or geocoder center for GPS Nearby.

## iOS root cause

The iOS location manager called `requestLocation()` and immediately accepted `locations.last`. It did not inspect `CLLocation.timestamp`, `horizontalAccuracy`, coordinate validity, or `accuracyAuthorization`. Core Location is allowed to deliver a cached location before a fresh fix; iOS therefore could launch the 3 km `MKLocalSearch` around a stale prior position. The same accepted coordinate then became the distance origin, making the list internally consistent but geographically wrong. The Add Restaurant view also did not refresh the GPS center after foregrounding, and reduced-accuracy location was presented without disclosure.

The MapKit query itself did not intentionally use city center, map camera center, reverse-geocoder placemark center, previous restaurant coordinates, or hardcoded Hangzhou as Nearby center. The failure was earlier: an unqualified cached `CLLocation` was treated as current.

## Implemented iOS contract

- Location acquisition now starts high-accuracy updates and remains in locating state until a valid fresh fix arrives or a 12-second timeout occurs.
- A usable full-accuracy fix must have a valid coordinate, nonnegative horizontal accuracy, timestamp no older than 15 seconds, at most 5 seconds of future clock skew, and horizontal accuracy at or better than 1,000 m.
- Reduced-accuracy fixes are accepted only as reduced accuracy, with a bounded 10 km horizontal accuracy, and the UI explicitly warns that Nearby may be offset. The project has no temporary-full-accuracy purpose-key configuration, so the fix does not pretend to request temporary precision that is not configured.
- Nearby query center, reverse-geocode coordinate, distance origin, and displayed current coordinate are the same accepted `CLLocation`.
- Every candidate distance is recomputed with `CLLocation.distance(from:)`, then filtered to 3 km and sorted nearest-first independently of the MapKit response/region ordering.
- Returning to the foreground requests a new fix. A movement update replaces both query center and distance origin.
- Denied, stale/inaccurate timeout, empty, loading, and failed states remain safe and keep city search, link import, and manual add available.
- Manual add no longer initializes its map camera at a hardcoded Hangzhou coordinate when GPS is unavailable; it starts with automatic MapKit positioning until the user selects, locates, or geocodes a real position.

## Shared deterministic coordinate

`contracts/fixtures/nearby-location.v1.json` is consumed by Web and iOS tests. It fixes the input GPS at `30.2741, 120.1551` and provides candidates at approximately 40 m, 420 m, and 2 km. Tests assert that both platforms use this origin, compute the expected distances, and keep the 40 m restaurant first without depending on Apple Maps or AMap POI names.

## Automated verification

- Web: the complete Vitest suite passed (`49` files, `342` tests); the shared-coordinate AMap test passed; application TypeScript, worker TypeScript, and the Vite production build passed. Vite emitted only its existing large-chunk advisory.
- iOS acquisition unit tests passed on the final code, including fresh/stale fixes, delayed first fix, reduced accuracy, denied permission, movement, foreground refresh, city fallback, distance ordering, shared coordinate, dedupe, WantToGo, and Visited behavior.
- Four focused iOS UI tests passed on the final code: automatic Nearby → WantToGo, city search/no-result → Visited, ordinary URL import → explicit confirmation, and denied location → manual add.
- The complete iOS unit run passed all acquisition tests. One unrelated `SyncCoordinatorTests.networkRecoveryAutomaticallySyncs()` expectation fluctuated during that concurrent run; its immediate isolated rerun passed. No SyncEngine code was changed.
- Debug and Release simulator builds both passed with code signing disabled. Release completed full-module optimization and validation.
- Full-repository ESLint remains red on pre-existing errors in unrelated Community/backup/photo/sync test files. None of those files differs from `origin/main`, and they were not changed for this task.

## Manual real-iPhone smoke

1. Open Add Restaurant and confirm it immediately shows locating, then current address and Nearby without tapping Locate.
2. Confirm the address is plausible and the first several restaurants are genuinely near the device; compare approximate walking/straight-line distance for at least one known 40–200 m place.
3. Repeat on Wi-Fi and cellular. The provider result set may vary, but the logged/observed GPS center and distance order must not jump to a city/camera center.
4. Move a meaningful distance or background/foreground the app; verify the address, query center, distances, and order refresh.
5. Force-quit/relaunch and verify no stale prior location is shown before a fresh fix.
6. Deny location and verify city search, link, and manual add remain usable.
7. Disable Precise Location and verify the “当前为大致位置” disclosure appears; re-enable Precise Location and retry.
8. Exercise Nearby/search/link/manual candidates through both “我去过” → Record Visit and “我想去” save paths, including an existing restaurant to confirm dedupe/repeat-visit behavior.
