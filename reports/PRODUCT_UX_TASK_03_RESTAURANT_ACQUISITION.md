# Taste Map Product UX Correction — Task 03

## Scope

Task 03 restores the formal Restaurant acquisition flow without changing
SwiftData schema, SyncEngine, Worker, D1, Production configuration, or signing:

1. Search Restaurant.
2. Nearby Restaurant from a fresh CLLocation.
3. External Share to Taste Map.
4. One manual-add fallback for places absent from map providers.

## Product result

### Add Restaurant information architecture

- Removed the user-facing `粘贴餐厅链接` section from the normal Add Restaurant
  screen. The HTTPS/parser infrastructure remains available to the Share
  Extension and pending-import flow.
- Search and Nearby remain first-class flows.
- Consolidated the former “地图上搜不到？” section and nested button into one
  tappable card:
  - `手动添加餐厅`
  - `适合地图上搜不到的小摊、快闪店、私房店和新开门店`
- Location denial does not block search or manual creation.

### External Share

- Apple Maps, AMap, generic HTTPS pages, URL/text payloads, address-only text,
  and coordinate-only text enter the same automatic recognition flow.
- Address-only input falls back to a scoped provider search.
- Coordinate-only input uses that coordinate as a 3 km Nearby query center.
- The normal Add Restaurant screen exposes no manual paste field.
- Pending shared payloads remain isolated in the existing App Group store and
  are consumed only after an explicit user action.

### Nearby GPS

- A fresh CLLocation is still required; stale, invalid, and excessively
  inaccurate fixes never reach the provider query.
- Reduced Accuracy is represented honestly and uses the coordinate actually
  supplied by the system.
- The exact GPS fix is used for the 3 km provider query, result distance
  calculation, and near-to-far sort.
- Foreground refresh and movement request a new fix instead of reusing a map
  camera, city center, geocoder center, or previous Restaurant coordinate.

### Candidate preview and explicit actions

Every Search, Nearby, Share, and Manual candidate now opens a common standard
Restaurant Detail presentation before mutation:

1. cover / Food & Dining fallback;
2. city, name, and address;
3. explicit `我去过 / 我想去` actions;
4. available reference price / phone / hours (or an honest unavailable state);
5. Apple Maps location and directions;
6. honest rating availability;
7. user-photo empty state.

`我想去` creates or reuses a Restaurant only after confirmation. `我去过`
continues to the existing Visit editor. Browsing candidates creates no local
Restaurant and queues no mutation.

### Dedupe

- Exact provider identity is classified separately and may reuse the existing
  Taste Map Restaurant automatically after the explicit action.
- A same-name/address/coordinate candidate from another provider is classified
  as a probable cross-provider match. The confirmation CTA remains disabled
  until the user confirms it is the same Restaurant.
- Provider IDs remain external identities; the Taste Map Restaurant UUID stays
  stable.

## Automated acceptance

### Unit / integration

PASS:

- `RestaurantAcquisitionTests` (24 tests)
- `Task09PendingImportTests` (3 tests)

Coverage includes fresh/stale/reduced location, movement/foreground refresh,
fixed-coordinate distance ordering, broad provider query merge, empty/denied
states, Apple Maps and AMap parsing, generic HTTPS safety, address-only share,
coordinate-only share, manual identity, offline WantToGo, exact identity,
probable cross-provider classification, provider-neutral sync contracts, pending
payload expiry, malformed payload rejection, and duplicate pending imports.

### UI flows

PASS:

- Nearby → candidate preview → WantToGo → global Restaurant Detail
- city search empty state → result → candidate preview → Visit editor
- automatic External Share recognition → preview → WantToGo
- denied location → manual Restaurant → preview → WantToGo

### Build

- Debug iPhone Simulator: PASS
- Release iPhone Simulator: PASS
- Share Extension embedded validation: PASS

## Screenshot evidence

All images were captured from the same Task 03 code using the iPhone 17 Pro
iOS 26.5 simulator.

- Nearby and single manual entry:
  `reports/product-ux-correction-assets/task-03-restaurant-acquisition/final/52E29F06-B92F-416B-93BE-8CF28DDE195B.png`
- Nearby standard candidate preview:
  `reports/product-ux-correction-assets/task-03-restaurant-acquisition/final/A339D6EE-F75D-4527-AEB1-E43376ABA095.png`
- Search candidate preview:
  `reports/product-ux-correction-assets/task-03-restaurant-acquisition/final/A416F425-6F13-43BD-9074-767D943B2350.png`
- External Share recognition:
  `reports/product-ux-correction-assets/task-03-restaurant-acquisition/final/6E8EF4CE-7E9C-43D5-8A03-D4A277C68BA6.png`
- External Share standard preview:
  `reports/product-ux-correction-assets/task-03-restaurant-acquisition/final/DDECD770-A90C-4452-BF6D-E6897FCE65DC.png`
- Manual Restaurant form:
  `reports/product-ux-correction-assets/task-03-restaurant-acquisition/final/7CA61B6A-6A90-42D3-84AD-7D57841C9AD8.png`
- Manual Restaurant standard preview:
  `reports/product-ux-correction-assets/task-03-restaurant-acquisition/final/989DF6AE-2BAB-4330-89D4-1E10465FE400.png`

## Real-device manual acceptance remaining

These require Lafayette’s real iPhone and are not represented as automated
passes:

- Apple Maps Share → Taste Map.
- AMap Share → Taste Map.
- a social/web URL and plain address Share → Taste Map.
- precise versus Reduced Accuracy state.
- real Nearby ordering at the current physical location.
- foreground refresh after physical movement.

## Safety boundary

- Production accessed: no.
- Worker/D1/R2 changed: no.
- SwiftData schema changed: no.
- SyncEngine changed: no.
- signing/capabilities/App Icon changed: no.

