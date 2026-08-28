# Restaurant Acquisition Flow

This document records the functional parity audit and native iOS design for adding a Restaurant. The React/Web implementation remains a product-logic reference; this change does not modify its UI.

## Functional parity audit

The Web baseline is `src/components/AddRestaurantModal.tsx`. Its server-side URL evidence parser is `worker/externalRestaurantLinkResolver.ts`, exposed to the Web through the legacy `/api/external-place/resolve` route in `worker/index.ts`.

| Web capability | Web implementation | Previous native iOS state | Native restoration |
| --- | --- | --- | --- |
| Add Restaurant hub | `AddRestaurantModal` owns nearby, search, link, manual, and final recording steps | Missing; the global add action opened only `RestaurantSearchView` | `AddRestaurantView` is the global hub; the focused picker remains available where an existing flow only needs MapKit search |
| Nearby Restaurants | GPS lookup, 3 km POI query, up to eight candidates, detected city/address, retry/empty states | Missing | Current Core Location coordinate + `MKLocalSearch`, 3 km filter, distance sorting, five visible results and an explicit retry/empty/denied state |
| Name/address search | AMap text search | Present only as a standalone MapKit search page | MapKit search is embedded as one module in the hub and accepts name or address text |
| Explicit city | Search city input and region-aware AMap query | Missing | City is a separate persisted field. MapKit resolves a city region before searching, so a user in Hangzhou can search Shanghai, Tokyo, or New York |
| Location is optional | Manual/search/link paths remain available when geolocation fails | Partly true at app launch, but there was no full acquisition fallback | Location denial only changes the Nearby section. City search, link import, and manual placement remain enabled |
| Restaurant link import | Apple Maps, AMap, ordinary HTTPS Restaurant pages, and shared text | Missing | Local safe parser handles known structured URLs; authenticated `/api/v1/external-place/resolve` reuses the existing Worker evidence parser and returns candidates or a MapKit search fallback |
| Confirmation before creation | Link/search results are selected before `onAdd`/`onRecordExisting` | MapKit results were explicit, but no other source existed | Every source produces a `RestaurantCandidate`. Browsing and resolving never touches SwiftData; only “加入想吃” or “记录去过” does |
| AMap identity | `amapPoiId` plus the P0 global identity contract | Not reachable from native UI | AMap link evidence becomes `placeIdentities: [{ provider: amap, externalId }]`; no Apple identity is fabricated |
| Apple Maps identity | Link evidence and native MapKit stable identifier | MapKit search only | Both MapKit results and Apple links preserve `apple_maps` external identity when available |
| Ordinary Restaurant URL | Safe server fetch with redirect, private-network, size, type, and timeout controls | Missing | Native sends HTTPS link/share text to the authenticated versioned Worker route; the existing SSRF protections remain authoritative |
| Manual Restaurant | Name, location, optional supporting text; intended for stalls/private/new venues | Missing | Native sheet requires name, city, and selected coordinate; address is optional. The coordinate can come from current location, address lookup, or a map tap |
| Duplicate protection | Existing AMap lookup plus restaurant history | Native checked Apple ID, then name/address/distance | Provider-neutral match checks every `placeIdentities` key first, then cautious normalized name/city/address + distance. A fuzzy cross-provider match merges the new identity into the existing Restaurant |
| Offline-first | Web local data plus later server sync | Existing native local-first store/queue worked for MapKit candidates | All candidate types enter the same `LocalTasteMapStore` and persistent `SyncMutation` queue. Network/link resolution failure never blocks manual local creation |

## Native information architecture

`AddRestaurantView` is a modal hub with one scrollable hierarchy:

1. Product explanation: this is a Taste Map acquisition flow, and candidates are not saved automatically.
2. Nearby: current 3 km context, loading/result/empty/permission-denied/failure states.
3. Search: independent city and name/address fields, search CTA, inline result cards.
4. Other methods: link/share-text import and manual Restaurant.

Link import and manual entry are focused child sheets. The page uses the Core App slate gray-blue (`#506C8C`), cool white page, light blue-gray surfaces, navy-charcoal text, restrained corner radii, and subtle borders. It intentionally does not use the P4 poster theme.

## Candidate and identity rules

Every source yields the same `RestaurantCandidate` value:

- Taste Map assigns its own local `UUID`.
- Provider identities are zero or more `(provider, externalID, isPrimary)` values.
- MapKit supplies `apple_maps` when an `MKMapItem.Identifier` exists.
- AMap evidence supplies `amap` and never requires conversion to an Apple ID.
- Manual entry supplies `manual:tastemap:<uuid>` as a stable manual identity for the candidate.
- A generic page can supply `other` only when it has an actual external identifier; otherwise it remains search evidence until the user confirms a MapKit result or creates a manual Restaurant.

`LocalTasteMapStore` persists the identities into the existing `RestaurantJSONContractV1` payload; no SwiftData schema or P0 identity foundation is replaced.

## Creation and downstream behavior

- `loadNearby`, `search`, and `resolveLink` are read-only candidate operations.
- “加入想吃” calls the existing local-first WantToGo path and enqueues one Restaurant mutation.
- “记录去过” hands the candidate to the existing `VisitEditorView`; the existing Visit flow creates/reuses the Restaurant only when the Visit is saved.
- An existing WantToGo Restaurant still transitions to Visited after its first Visit.
- A repeated Visit still creates a separate Visit and never overwrites history.
- Link resolver/network failure produces a recoverable message and preserves city search/manual entry.

## API boundary and safety

The native client calls `POST /api/v1/external-place/resolve` using the same Taste Map access-token provider and single refresh recovery used by authenticated APIs. The Worker derives the viewer from authentication and does not authorize using any client-supplied user ID. Candidate database queries retain the existing rule: a viewer sees their own private Restaurant or a Restaurant exposed by a public Visit.

The legacy Web endpoint remains unchanged so the current Web app is not broken. Production data is not migrated or touched by this implementation. No provider secret, Cloudflare secret, or token is added to iOS.

## Intentional native differences

- MapKit replaces the Web AMap SDK for native search and nearby discovery; AMap remains supported as an external identity/link source.
- SwiftUI sections and focused sheets replace the Web modal's step layout; capabilities and explicit confirmation are preserved rather than pixel layout.
- The native nearby hub shows five initial candidates from an eight-result model cap to avoid crowding; search is available for the rest.
- Share Extension is still out of scope. Paste/share-text import is restored without inventing another target or capability.

## Regression boundary

This work does not change Bundle Identifier, Team, signing, capabilities, auth/session semantics, Sync V1 architecture, SwiftData schema, Premium, P4 analytics, App Icon, or Production infrastructure. Restaurant Detail, Visit, Photo, Dish, Lists, Roulette, Discovery, Community, and analytics continue to consume the same `Restaurant` domain model.
