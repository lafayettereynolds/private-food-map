# P4-I — Product hardening and final acceptance

更新时间：2026-08-29

## Scope

P4-I closes the native iOS P4 product surface without adding a new product feature. It audits and hardens P4-A through P4-H, keeps the React/Web product unchanged, introduces no new SwiftData or D1 schema, does not add StoreKit, and does not access Production Worker or Production D1.

## Shared analysis definitions

The five analysis families use one native definition source:

- ratings are calculated only from non-`nil` `Visit.rating` values;
- spend is calculated only from non-`nil` `Visit.myActualSpend` values and never inferred from Dish prices;
- averages use the arithmetic mean of recorded values;
- median uses the center value for odd samples and the mean of the two center values for even samples;
- coverage is recorded-value count divided by eligible-Visit count;
- missing data remains missing rather than becoming zero;
- data-sufficiency thresholds are centralized and reports must show a truthful low-data state instead of fabricating a conclusion.

Restaurant identity for analytics is projected through a provider-neutral connected graph. Taste Map contract IDs, remote IDs, Apple Maps IDs and every `placeIdentity(provider, providerPlaceID)` participate. Transitive aliases resolve to one deterministic active Restaurant representative. Soft-deleted Restaurants never participate in a merge and cannot revive an active or deleted record. This read-only projection does not alter SwiftData identity, Sync V1 ownership or server data.

## Period, deletion and determinism contract

- Monthly and annual periods use the same injected `Calendar` and half-open `[start, end)` boundaries.
- The current partial month/year is explicitly labelled as partial. Historical periods remain complete periods.
- The persisted Visit timestamp is an absolute instant. Because the model does not retain the timezone originally selected for a Visit, reports interpret it in the report's selected/current calendar timezone. P4-I does not invent historical timezone metadata.
- Restaurant, Visit, Dish, Photo, Companion and Recommendation Source tombstones are excluded before aggregation. List and roulette projections retain their existing provider-neutral identity and tombstone filtering.
- Sorting and tie-breaking use stable evidence counts, normalized labels and stable identifiers. The same snapshot and calendar produce the same report and poster payload.

## Refresh, privacy and offline behavior

Analysis screens capture immutable `Sendable` snapshots on the main actor and run aggregation outside SwiftUI body evaluation. Their revision key includes active record counts plus latest update and deletion timestamps, so create/edit/delete causes a targeted report refresh without a global cache flush. Reports are view-local; no cross-account durable analysis result or poster payload is persisted.

The shared poster pipeline exports only prepared report DTOs and resolved presentation images. It does not export Apple subject, email, access/refresh tokens, provider storage keys, private Visit notes or internal linked-user identifiers. The exporter supports local/cached image resolution while offline. Temporary PNGs live only in the dedicated Taste Map share directory, are limited by age and count, and cleanup never touches the user's Photos library or files outside that directory.

## Premium and protection boundaries

The five analysis pages and their render/save/share operations remain protected by the centralized P4-H feature registry and entitlement service. Free users keep all core recording, Restaurant, Visit, WantToGo, basic Photo/Dish/Profile/social, ordinary list and roulette behavior. Direct navigation cannot bypass a gate, and an unknown/stale entitlement does not silently become Premium. P4-I does not add products, prices, purchases, restore behavior or StoreKit transaction handling.

## Persistence and backend impact

P4-I adds no SwiftData model, Sync V1 entity, Worker route, D1 table or migration. Existing migrations remain immutable. Development D1 verification is read-only; Production resources are not queried, migrated, deployed or written. Existing legacy Web fields and data remain untouched.

## Acceptance evidence

Acceptance requires all native unit tests, Worker/Web tests and migrations, TypeScript checks, Vite build, Preview-compilable Simulator builds, full Simulator UI regression, Release Simulator build, and signed available-device build/install to pass. The final task report records exact counts, destinations, known pre-existing warnings and any unavailable manual hardware-only interaction separately; absence of a manual check is never reported as an automated pass.

Final 2026-08-29 evidence:

- native unit tests: 318/318 passed on iPhone 17 Pro Simulator;
- native UI tests: 33 tests passed (36 expanded runs), zero failures, with one conditional P1-store migration UI test skipped because its external pre-upgrade fixture was not supplied; additive SwiftData migration tests passed in the unit suite;
- Web/Worker Vitest: 290/290 passed; TypeScript app and Worker checks passed; Vite production build passed with only the pre-existing bundle-size advisory;
- all 11 local incremental migration suites passed; Development D1 reported no migrations to apply and read-only orphan checks returned zero;
- Debug Simulator, Release Simulator and signed iPhone device builds passed; the signed app installed on the connected iPhone;
- automated device launch was denied by iOS because the development profile had not been explicitly trusted on the device, so hardware-only P4 interaction, Photos permission, Share Sheet and haptic checks were not claimed as executed;
- Production Worker and Production D1 were not queried, migrated, deployed or written.
