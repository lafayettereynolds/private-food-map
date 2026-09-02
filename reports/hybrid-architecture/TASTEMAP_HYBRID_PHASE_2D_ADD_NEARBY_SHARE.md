# Taste Map Hybrid Phase 2D — Add Restaurant, Nearby, and Share

Date: 2026-09-03
Branch: `feature/hybrid-remaining-ui-batch`
Production owner: SwiftUI (`NATIVE_PRIMARY`)
Migration status: Add Restaurant / Nearby `HYBRID_INTEGRATED`, not `HYBRID_PRIMARY`

## Outcome

The formal Browser and Capacitor hosts now consume one compact React Add Restaurant page with the complete Search, Nearby, external Share, and single Manual Add product contract. Provider, location, identity, dedupe, ownership, and persistence decisions remain native on iOS through typed `TasteMapNative.v1` methods.

No JavaScript database, location fallback, provider identity store, credential path, duplicate Restaurant model, minimal confirmation page, or second Hybrid page skeleton was introduced.

## Regression inventory and closure

| Current regression | Expected contract | Root cause | Closure |
| --- | --- | --- | --- |
| Hybrid Search filtered already-recorded Restaurants | real provider Search by query and city | migration placeholder was mistaken for acquisition | `acquisition.search` now reaches the existing native provider service |
| Nearby reused generic location/read behavior | fresh CLLocation, 3 km query, real distance order | capability boundary was not connected to the page | `acquisition.nearby` validates fresh accuracy/timestamp and sorts measured distance |
| Share and Manual opened `acquisitionNative` | four capabilities remain visible in one React page | native capability ownership was confused with route ownership | Share and Manual are typed acquisition actions in the shared UI |
| Share ingestion opened Native-owned Add | Add is already Hybrid-owned in the route registry | pre-migration handoff survived the route migration | normalized Share now opens the persistent Hybrid Add route and emits only its fingerprint |
| Search/Share candidates could enter a second confirmation flow | candidate opens canonical Restaurant Detail | provider selection was coupled to legacy native presentation | selection caches an owner-visible canonical read projection and routes to global Detail |
| probable cross-provider match could be silently merged | explicit confirmation before merge | dedupe classification was not exposed | bridge returns `exactProvider` / `probableCrossProvider`; probable match requires confirmation |
| Browser candidate temporarily received owner edit rights | read candidate cannot be edited/deleted before ownership exists | Browser projection reused owned capabilities | candidate capability projection now denies edit/delete and preserves Record/Want/List/Share |

## Architecture

```text
TasteMapRestaurantAcquisitionScaffold (one React UI)
    -> TasteMapPlatform.acquisition
    -> Browser adapter: existing Web mapService
    -> Native adapter: TasteMapNative.v1
        -> MapKitRestaurantSearchService
        -> LocationPermissionManager + RestaurantLocationFixPolicy
        -> RestaurantDistanceOrdering
        -> ExternalRestaurantLinkParser / authenticated resolver
        -> RestaurantDeduplicator
        -> owner-visible canonical Restaurant reference
```

Candidate browsing never creates a `Restaurant`. The canonical local Restaurant/Visit mutation paths remain responsible for Want to Go and Record Visit. React never provides an owner ID; transient candidate state is scoped to the active native account and cleared on sign-in/logout.

## Product gates

| Gate | Result |
| --- | --- |
| PRODUCT CONTRACT | PASS — Search / Nearby / Share / one Manual entry |
| ONE REACT UI | PASS — shared acquisition scaffold in Browser and Capacitor |
| CURRENT CAPABILITY PRESERVATION | PASS — provider, GPS, Share Extension, dedupe, canonical Detail preserved |
| BROWSER ↔ CAPACITOR | PASS — same React component and CSS; adapter-only capability difference |
| REFERENCE PARITY | PASS — compact approved hierarchy; no large nested-card fork |
| FUNCTION / SEMANTIC | PASS — real provider acquisition, honest location/error states, owner authority |
| NEGATIVE CONTRACT | PASS — no paste-link primary input, duplicate Manual entry, Add tab, no-op action, city-center GPS fallback, or minimal confirm page |

## Verification

| Verification | Result |
| --- | --- |
| TypeScript project/Worker typecheck | PASS |
| Hybrid platform + global Product Contract | PASS — 30 tests |
| Native acquisition + Hybrid integration | PASS — 32 tests |
| Debug fixed-Simulator build | PASS |
| Fixed Simulator install/launch | PASS — iPhone 17 Pro, same booted UDID |
| Browser Mobile render | PASS |
| Release Simulator / generic device / purity | recorded with the module commit after formal resource restoration |

## Visual evidence

- Browser Mobile: `reports/hybrid-architecture/screenshots/phase-2d/browser-mobile-add-restaurant.png`
- Capacitor iOS: `reports/hybrid-architecture/screenshots/phase-2d/capacitor-add-restaurant.png`

## Remaining manual gates

- real iPhone full/reduced/denied Location smoke;
- Development AMap/MapKit result comparison at the same coordinate;
- real Share Extension ingestion from Apple Maps, AMap, URL, and text;
- Lafayette visual acceptance and explicit approval before any `HYBRID_PRIMARY` switch.

No Production, Worker, D1, R2, StoreKit production configuration, schema, SyncEngine, or signing change was made.
