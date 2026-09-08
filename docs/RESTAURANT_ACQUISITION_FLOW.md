# Restaurant Acquisition Flow

This document records the functional parity audit and native iOS design for adding a Restaurant. The React/Web implementation remains a product-logic reference; this change does not modify its UI.

## Functional parity audit

The Web baseline is `src/components/AddRestaurantModal.tsx`. Its server-side URL evidence parser is `worker/externalRestaurantLinkResolver.ts`, exposed to the Web through the legacy `/api/external-place/resolve` route in `worker/index.ts`.

| Web capability | Web implementation | Previous native iOS state | Native restoration |
| --- | --- | --- | --- |
| Add Restaurant hub | `AddRestaurantModal` owns nearby, search, link, manual, and final recording steps | Missing; the global add action opened only `RestaurantSearchView` | `AddRestaurantView` is the global hub; the focused picker remains available where an existing flow only needs MapKit search |
| Nearby Restaurants | GPS lookup, 3 km POI query, up to eight candidates, detected city/address, retry/empty states | Missing | Current Core Location coordinate + `MKLocalSearch`, 3 km filter, distance sorting, five visible results and an explicit retry/empty/denied state |
| Name/address search | AMap text search | Present only as a standalone MapKit search page | MapKit search is embedded as one module in the hub and accepts name or address text |
| Explicit city | Search city input and region-aware AMap query | Missing | City is a separate persisted field and a hard geographic scope. China searches use MapKit first; other countries use a global OpenStreetMap POI fallback first. Results outside the resolved metropolitan boundary are discarded, so a user in Hangzhou can search Shanghai, Tokyo, or New York without silently receiving current-city matches |
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

- Native nearby discovery continues to use MapKit. Explicit city search uses MapKit in China and a global OpenStreetMap POI fallback outside China; AMap remains supported as an external identity/link source.
- SwiftUI sections and focused sheets replace the Web modal's step layout; capabilities and explicit confirmation are preserved rather than pixel layout.
- The native nearby hub shows five initial candidates from an eight-result model cap to avoid crowding; search is available for the rest.
- Share Extension is still out of scope. Paste/share-text import is restored without inventing another target or capability.

## Regression boundary

This work does not change Bundle Identifier, Team, signing, capabilities, auth/session semantics, Sync V1 architecture, SwiftData schema, Premium, P4 analytics, App Icon, or Production infrastructure. Restaurant Detail, Visit, Photo, Dish, Lists, Roulette, Discovery, Community, and analytics continue to consume the same `Restaurant` domain model.

## 2026-09-06 coordinate-reference correction (current acquisition behavior)

The original five/eight-result limits above are historical. The current nearby page progressively reveals the accepted, distance-sorted snapshot without repeating GPS or provider requests.

Two independent, fresh iPhone fixes reproduced the reported mismatch: a public restaurant approximately 83–84 metres away after reference normalization was shown at approximately 590–594 metres when raw Core Location and mainland provider coordinates were compared numerically. Reported horizontal accuracy was approximately 9.2 and 4.5 metres; both fixes were under one second old when accepted. This supports a coordinate-reference error, not stale GPS. Exact user coordinates are deliberately excluded from this document.

- Acquisition sensor origins are explicitly WGS-84. Fresh provider candidates carry an in-memory reference; clones and repeated ranking retain it. No persistent Restaurant/backup schema or saved coordinates are migrated.
- The current mainland MapKit backing service was empirically verified to use GCJ-02 numeric query/result coordinates. This is an observed provider policy, **not** a universal guarantee in Apple's generic MapKit documentation. Selection uses the actual reverse-geocoded ISO country, never the UI city, language, IP, or a rectangular region guess. Mainland CN uses that policy; HK/MO/TW and other valid regions retain WGS-84. Unknown origin/candidate country fails the affected nearby request/batch instead of presenting an unverified distance.
- Query conversion is local to MapKit. Distance comparisons transiently normalize a known GCJ-02 endpoint back to WGS-84; an overseas sensor endpoint is never shifted merely because the other endpoint is in mainland China. The public-provider coordinates themselves remain unchanged. Photon retains its WGS-84 contract and does not inherit MapKit's local query conversion.
- The older CLGeocoder reverse-geocoding path receives WGS-84; the iOS 26 MapKit reverse-geocoding path receives its provider origin. City/name search can proceed without a GPS bias if origin resolution fails.
- Browser AMap GPS conversion must explicitly succeed with valid coordinates. Errors, missing/invalid results, SDK failures, and timeout reject rather than silently returning raw GPS as an AMap point. Independent city search/manual entry remain available.
- No restaurant is specially pinned to first place. The accepted snapshot is measured and sorted by straight-line distance, with the existing deterministic tie-break. This is not walking-route distance or a claim that the provider returns every nearby business.

Source verification: 74 native tests across coordinate normalization, acquisition lifecycle, MapKit request policy, bridge navigation, and paused marker shape passed; 115 browser/bridge/navigation tests passed. Two public-point probes through the actual search service produced matching distances from equivalent GPS/provider inputs, and repeated ranking retained them. These are code/service checks, not final corrected iPhone acceptance.

Remaining boundary: legacy saved coordinates have no reliable datum metadata and are not guessed or bulk-converted. Other distance consumers using legacy stored coordinates, manual-placement persistence, and broader provider/country validation remain separate audit items. Corrected real-device installation and repeat sensor-to-nearby verification must be recorded before calling GPS fully accepted.

### Corrected iPhone check — build 906.17

The signed `DebugPrivatePreview` 906.17 artifact was installed on the requested iPhone 17 Pro Max without uninstalling, changing accounts, or editing Restaurant/Visit data. All 18 formal Web resources matched source-stage and built-app bytes. The normal Hybrid UI and current account were observed in iPhone Mirroring.

First fresh nearby load visibly showed 三毛烤鸡(南瓦坊店) at **80 m**, fifth on the first screen; after returning to Map and re-entering Add, the visible distance was **78 m**, still fifth. Four observed result batches were approximately 79.54, 78.69, 78.69, and 77.99 m; all used non-simulated fixes and returned 37 accepted candidates. Provider order was not pinned: closer candidates correctly preceded this restaurant. Raw GPS was not written to this report. This accepts the reported fresh acquisition distance mismatch on this device/location, not every GPS/legacy-map consumer globally.

Four public query anchors (南瓦坊、武林广场、湖滨 in77、中国丝绸博物馆) also retained normalized distances and repeated-ranking stability. Provider result membership varied slightly across separate requests at two anchors; this is not an exhaustive-POI acceptance claim. Two fixed-Simulator Hybrid UI tests passed for search pagination and the restored historical pending-marker shell. The separate Release artifact passed the formal purity scan. Treasure-chest candidate rendering remains disabled.
