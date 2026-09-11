# Taste Map Hybrid Architecture

Status: Batch 1 shared Product UI and Batch 2 typed Native capability closure complete; production route switch not approved.
Contract: `TasteMapNative.v1`
Updated: 2026-09-03

## 1. Architectural decision

Taste Map will converge on one React product UI that runs in two hosts. “One React UI” governs product structure and page chrome; it does **not** require one cross-platform map engine:

- Browser: React → `TasteMapBrowserAdapter` → IndexedDB / existing Web services, with the existing Web map provider.
- iOS: the same React page chrome in a Capacitor `WKWebView` → `TasteMapNativeAdapter` → `TasteMapNative.v1` → native services and current-user SwiftData, with the established Native MapKit / `MKMapView` surface.

SwiftUI remains the production default and rollback implementation during incremental migration. Phase 2A embeds the signed local Hybrid runtime in the existing Taste Map target and promotes Profile and Restaurant Detail to `HYBRID_INTEGRATED`. Phase 2B adds My Map / My List. Batch 1 integrates the remaining Product UI through the same React/CSS and Batch 2 connects its writes and system actions to existing Native services. None of these statuses switches the Release root.

```text
Canonical Page Templates + shared React components
                         │
                  TasteMapPlatform
                   ┌─────┴─────┐
                   │           │
         Browser adapter    Native adapter
                   │           │
        IndexedDB/services   TasteMapNative.v1
                               │
                    explicit native services
                 (SwiftData/Auth/Sync/etc. by capability)
```

The UI layer never imports Capacitor or native implementation details. Platform selection occurs once in `tasteMapPlatformResolver.ts`.

## 2. Source layout

| Path | Responsibility |
| --- | --- |
| `src/platform/TasteMapPlatform.ts` | Versioned DTOs, capability registry, service interface, errors and UI-state vocabulary |
| `src/platform/TasteMapBrowserAdapter.ts` | Browser implementation using the existing data layer or an injected source |
| `src/platform/TasteMapNativeAdapter.ts` | Capacitor host detection, v1 envelopes, validation, structured error mapping |
| `src/platform/TasteMapBridgeProjection.ts` | Explicit DTO → shared Web presentation-model projection |
| `src/hybrid/app/HybridAppShell.tsx` | Shared app shell, auth bootstrap, event subscription and persistent Hybrid/native route rendering |
| `src/components/MyMapBrowsePage.tsx` | Canonical My Map / My List React page and shared `MapBrowseState` |
| `src/components/MapView.tsx` | Browser-only Web map renderer, fixed circle anchors, natural city overlap, reversible wider-area Restaurant-image representatives and exact-coordinate member lists |
| `src/components/NativeMapSurface.tsx` | Thin React declaration of the iOS map rectangle, filtered marker presentation and React-control exclusions |
| `src/hybrid/routes/HybridRouteRegistry.ts` | Route readiness, hashes, deep-link parser and ownership declaration |
| `ios/TasteMap/TasteMap/Hybrid/TasteMapHybridMapSurface.swift` | Persistent MapKit adapter that reuses `RestaurantMapView`; it does not create a second `MKMapView` implementation |
| `ios/TasteMap/TasteMap/Hybrid/` | Native DTOs, current-user data service, dispatcher, navigation coordinator and persistent production host |
| `ios/TasteMap/HybridRuntimeResources/` | Signed local React bundle and Capacitor configuration embedded in the formal Taste Map target |
| `hybrid/capacitor-shell/` | Internal Capacitor host that consumes signed local `dist/` assets |
| `hybrid/scripts/` | Reproducible build, sync, Debug fixture installation and Release-purity checks |

## 3. `TasteMapNative.v1`

2026-09-09 personal-filter increment: optional `predictedLiking` carries a
historical weighted-rating estimate and real sample counts, separately from
`personalTastePercent` and the future calibrated-probability channel. Native
remote/cache/bridge DTOs preserve the optional object without recomputing it in
React. `minimumPredictedLikingOutOfTen`, `minimumTasteMatchPercent` and
`predicted_liking` sorting extend the existing Discovery query; Native verifies
the server's applied-query echo and rejects an old server that ignores them.
Only For You supports these filters. No auth, persistence, route-default or
permission change is implied. Worker computes from existing owner aggregates,
without a new D1 query or cross-owner cache. Deployment/runtime acceptance remains
an integration gate.

All native calls use one Capacitor plugin method, `TasteMapNative.invoke`, with a typed envelope:

```json
{
  "request": {
    "version": 1,
    "requestId": "opaque-client-generated-id",
    "method": "restaurant.get",
    "payload": { "id": "restaurant-id" }
  }
}
```

Every response echoes `version` and `requestId` and contains exactly one of `result` or `error`. Errors are stable objects with `code`, `message`, `recoverable`, and optional non-sensitive `details`. Unsupported versions, invalid request IDs, invalid payloads, missing auth, missing objects and unavailable capabilities are distinguishable. JavaScript never receives raw Swift errors.

The v1 contract defines:

- runtime and capability negotiation;
- auth status/sign-in/logout shapes (no token fields);
- current Profile;
- Restaurant get/list, owner-scoped batched map viewport queries, and a presentation-only `map.surface.update` contract;
- Visit contract readiness;
- Sync status/run;
- haptics, system share, fresh location, photo-library pick and camera capture;
- StoreKit products/purchase/restore/manage and server-backed Premium status;
- permissions status/System Settings, Backup/Import and Account Delete route handoff;
- navigation back to native-owned routes.

Discovery engagement uses explicit interaction identity rather than a generic social destination. A visible Activity action carries the applicable `activityID`, authoritative `visitID`, `authorID`, and `restaurantID`; Like and Comment mutate/query the existing community interaction service by `visitID`, while WantToGo mutates the current user's Restaurant viewer state by `restaurantID`. Recommendation rows without an authoritative Activity/Visit target do not expose fake Like or Comment controls. Mutation responses return authoritative counts/state so optimistic UI can reconcile or roll back.

The optional Discovery `calibratedLikeProbability` field is a backward-compatible future model-output channel, not a new recommendation producer. Its value is displayable only with explicit validated calibration, sufficient evidence, an approved positive-feedback definition/version, model/calibration versions, validation sample count and unexpired validity. Native remote/cache/bridge and shared React preserve the same fields. Existing `personalTastePercent` retains its wire name for compatibility but means a matching index, never a probability. Missing/invalid attestation uses the shared `口味匹配度` fallback; no current production model emits an approved calibrated probability, and neither Visit-count milestones nor the public 7.5 admission rule define liking. This contract does not change the recommendation snapshot, eligibility, routing or source of truth.

Phase 2A formally implements runtime/auth status, Sign in with Apple, logout, Profile read, Restaurant read, Visit contract negotiation, selection haptics, typed navigation and event delivery in the shipping target. Phase 2B adds `map.viewport`, `map.surface.update`, `map.viewport.changed`, `map.restaurant.selected`, `location.current`, and throttled `location.changed` delivery. `map.viewport` remains the owner-scoped data projection. `map.surface.update` is presentation-only: React sends the filtered marker DTOs, product-state descriptors, its viewport rectangle and small React-control exclusion rectangles; Native places the persistent MapKit surface and reports actual viewport/selection changes. It carries no credentials, persistence objects or write authority. Batch 2 adds typed owner-scoped Visit/Dish/photo writes, Restaurant acquisition, camera/photo-library input, StoreKit, Sync, permissions and data/account route actions without moving persistence, ownership, provider, entitlement or security policy into JavaScript. The viewport request can carry bounds for bounded consumers, but the interactive My Map surface requests one full filtered result (capped at 300) and retains it while panning; the camera viewport is presentation state and never causes a marker-data replacement. The response contains lean owner-scoped marker/list DTOs plus stable unique-Restaurant totals for `去过 / 想吃 / 推荐`, and never serializes SwiftData entities. Scope totals are independent of bounds, filters and search so map gestures cannot make the primary labels jump; the active result's separate `totalCount` continues to describe the current query. Native-owned high-risk workflows keep their established Native screens/services behind specific typed methods; unsupported operations return `capability_unavailable` rather than pretending to succeed.

### 3.1 Discovery query channel (2026-09-06, interface stage only)

`discovery.page` is an additive bridge-v1 method negotiated by optional
`supportedCapabilities.discoveryPage`; absence means unavailable. It accepts
`mode`, requested `city` (empty delegates resolution to the server), `windowDays`
(7, or 30 for Trending only), and an optional paired `cursor` / `snapshotID`.
`forceRefresh` is first-page only. Native obtains the owner from the authenticated
session, not JavaScript, then calls the existing real Discovery API with those
inputs. No client-side filtering of the first twenty cards substitutes for a
city query, and the new channel does not invoke provider fallback.

The independent session coordinator binds the opaque server cursor to owner,
mode, normalized requested city, server-resolved city, trend window and the
accepted snapshot. Continuations pin resolved city and server `generatedAt`;
the returned `items` accumulate accepted pages in server order, deduplicated by
card ID, without reranking. `pagination` is `more` / `complete` / `unknown`, not
a total count. Auth reset and per-mode query revisions reject late results;
refresh invalidates pending append, and retries are not throttled. Public and
friends-visible pages remain in session memory; this channel does not mutate
legacy SwiftData placements or unsaved drafts. HTTP 401/403 clears every cached
scope of the affected mode. Other failures preserve only the same query's last
accepted snapshot and its cursor, with explicit structured freshness/issue.

This is not a UI migration: `content.snapshot`, Shell/Map recommendation state,
city/window controls and page controls still use their existing paths. The
earlier legacy refresh channel retains its per-mode fresh/cached/unavailable/
restricted statuses, force retry and isolated SwiftData read/write contexts.
The page result declares `engagementState: unknown` and
`interactionsAvailable: false`: the upstream page has no engagement counts, so
the reused item DTO's old zero defaults must not appear as verified counts.
Native page-target authorization, image authorization and authoritative social
hydration must be connected before UI consumption. Browser exposes the typed
method but advertises `discoveryPage: false` and rejects calls; it must not pair
real server cards with its legacy local social mutations. Browser authenticated
page production and the existing real social endpoints are a later bounded
stage, not a claimed parity completion.

### 3.2 Community city API (2026-09-06, source-only; not deployed)

Formal `CommunityAPI.feed` accepts an explicit city for `following` and `latest`.
The Worker applies its normalized city predicate before pagination, without
changing visibility or qualified-Visit eligibility. Empty city remains all-city;
it never selects GPS or Profile city. Feed cursors bind owner, scope and city;
reusing another query's cursor or an old unbound cursor requires first-page
refresh. Public-profile cursors retain their existing separate contract.

The additive optional response `city` lets Native fail closed when a specified
city reaches an older server that ignores it. Existing no-city callers and old
DTOs remain readable. This source-only slice adds no bridge UI consumer, Native
session overlay, cache write, route promotion or deployment. City-based Hybrid
display still requires authorized session targets/images and social hydration;
the unpublished friends-album HOLD remains unchanged. See
`reports/COMMUNITY_CITY_API_VERTICAL_SLICE_2026_09_06.md` for exact separable hunks.

### 3.3 Selected-city session presentation (2026-09-07)

`discovery.cityPage`, negotiated separately by optional `discoveryCityPage`,
accepts all five Discovery modes and a nonempty user-selected city. The optional
7/30-day window and paired cursor/snapshot fields retain the existing semantics.
It returns accumulated `discoveryItems` or `activityItems`, explicit pagination
and freshness, and does not replace `content.snapshot` or Map's canonical For You
snapshot. Native calls the real Discovery API for three modes and Community API
for Following/Latest; it never substitutes GPS/Profile city or filters a default
first page to impersonate a remote query.

`TasteMapDiscoveryCitySession` owns bounded current-owner/current-mode city pages
and their authorized Restaurant references, exact Activity targets and emitted
photo descriptors in memory only. Query revisions, cursor scope, auth epoch and
a ten-minute permission lifetime reject stale access; 401/403 revokes all city
overlays and pending results. Detail, Record Visit, WantToGo, Roulette and private
recommendation exclusions use these accepted references without creating a
persistent Discovery placement. Photo downloads remain authenticated and
revalidate the descriptor scope after awaiting. Restaurant-rating references
retain actual Discovery aggregates. Community engagement is supplied by its
existing response; Discovery has no authoritative engagement-read endpoint, so
those results remain `unknown` and do not expose fake zero social counts.

Only explicit DEBUG Visual QA uses an independent complete city test dataset:
Hangzhou, Shanghai, Beijing and New York each have 36 defined mock items per mode,
paged 20 then 16 through the same session coordinator. It does not enable network,
read the default first-page cache, or write fixture Restaurants. The response
marks `dataSource: debug_city_fixture`, and the shared UI must prominently say
`模拟数据`. Release excludes the producer. Production remains `remote`; the
Community city API source has not been deployed, so Following/Latest requests
to an older server fail closed instead of displaying an unrestricted city feed.
This is no route promotion or claim of production/phone acceptance.

## 4. Security and ownership boundary

Premium Gift (2026-09-07) extends `premium.status` with optional `source`,
`startedAt`, `statusText`, and `canManageSubscription`. Native's existing
PremiumEntitlementService remains the access authority and projects these fields;
React cannot infer access from a local profile tier or replace source precedence.
The Browser adapter consumes the existing server membership service. Gift records
are Taste Map user-scoped and independent of StoreKit records. Session generations
reject stale entitlement responses even for A→B→A. Admin lives on the Worker,
with real Bearer authentication and a server allowlist, outside the signed App UI.
No route owner or product capability is changed.

- The bridge exposes neither Apple identity/authorization tokens nor session refresh tokens.
- Keychain remains native-only.
- SwiftData model instances never cross the bridge; the service creates lean, Codable DTOs.
- Native queries are scoped by the current Taste Map user ID through existing ownership predicates.
- Restaurant visuals cross as allowlisted typed descriptors (`ownerPhoto`, `activityPhoto`, `publicUGC`, `foodCategoryVisual`, with legacy descriptor cases retained only for compatible decoding), never as arbitrary filesystem paths or binaries. Local resources are read through the allowlisted `tastemap-resource://` scheme handler.
- A descriptor preserves photo, Restaurant, Visit, source-owner, visibility, attribution, and export metadata as applicable. React owns presentation only; Native/Worker authority owns eligibility and source priority.
- The surface matrix is canonical: Personal Map uses owner photo → category; Search/Nearby/Detail/For You/Trending use owner → eligible public UGC → category; Following/Same Taste/Latest use viewer-visible activity photo → eligible public UGC → category. Photo uploader identity never becomes a system recommendation or trend source.
- Public other-user UGC is in-app-only with export disabled by default. It cannot enter posters, downloads, Backup, or external sharing without a separate explicit grant.
- Error logs contain method, opaque request ID and duration only. They do not log payloads, tokens or user content.
- The `HYBRID_DEVELOPMENT` runtime case and launch argument are compiled under `#if DEBUG`; Release has only `NATIVE_PRIMARY`.
- The formal Hybrid React entry is independent of the full Browser entry and does not link Browser cloud credential/photo-provider implementations.
- Release scanning covers the signed Web bundle separately and rejects credential vocabulary as well as fixtures, development URLs, local paths and secrets.

## 5. App shell, route contract and navigation ownership

The typed route model is the only identity exchanged between native and Hybrid navigation. Every route has a validated `surface`, an optional bounded identifier and an explicit owner. JavaScript can never request an arbitrary Swift type or selector.

Current integrated-route ownership is:

- Hybrid: My Map / My List, Discovery/Community, Add Restaurant/Nearby, current-user Profile, Restaurant Detail, Visit editor, Lists/Public Lists, public Activity presentation, Roulette, Analytics/Posters, Premium and Settings Product UI.
- Native: auth and account scope, persistence/write services, photo files/camera/Photos, location/provider, Sync, StoreKit/entitlement, Backup/Import, permissions/System Settings and destructive-account boundaries. SwiftUI continues to own the Release root and remains rollback UI.

The Hybrid shell supports canonical local routes including:

- `#/profile`
- `#/restaurant/:id`
- `#/map`
- `#/discovery`, `#/add`, `#/visit/:id`, `#/visitEdit/:id`
- `#/lists`, `#/publicList/:id`, `#/activity/:id`, `#/roulette`
- `#/analytics/:mode`, `#/premium`, `#/settings`

### Restaurant visual authority and performance

Worker social projections batch-load eligible Photo/Visit/Profile/Restaurant rows for the current result set and build a grouped `RestaurantUGCImagePool`; cards do not perform per-Restaurant photo queries. The pool applies existing visibility and block relationships plus deletion/moderation state, then returns a stable selection. Candidate identity matching preserves provider identity and may connect equivalent Restaurant records without exposing provider credentials.

Native owner surfaces query only the authenticated owner's Restaurant/Visit/PhotoAsset rows. Search and Nearby share the same resolution plan. The iOS map remains `MKMapView`/MapKit and renders either an owner photo or the same `FoodCategoryVisualID` meaning locally; it does not request public or merchant photos during marker rendering. Browser and Capacitor product routes use the same React components and descriptor renderer, while Native MapKit remains the platform-owned map engine.

React is the navigation truth while a Hybrid-owned page is visible. `TasteMapHybridNavigationCoordinator` is the transition boundary, not a second business stack: it keeps one Hybrid history plus at most one native presentation. The contract exposes `navigation.openHybrid`, `navigation.openNative`, `navigation.back`, and `navigation.current`, all with validation and structured errors. `navigation.openNative` rejects Hybrid-owned surfaces even if a stale caller constructs such a payload; Visit editor and Roulette always use the Hybrid navigation path. Native handoff remains reserved for native-owned capabilities such as List management and system Share.

Profile → Restaurant and Map → Restaurant append one Hybrid history entry. Hybrid → Native presents an existing SwiftUI route without destroying the persistent WebView. Back dismisses that native presentation first; otherwise it pops Hybrid history. Native → Hybrid delivers the canonical route to the same long-lived shell. My Map / My List keeps one `MapBrowseState` containing mode, scope, filters, sort, city, search, viewport and selection; changing mode or returning from Restaurant Detail does not construct a second query state. Discovery remains mounted after first activation so its selected feed tab/filter, scroll position and optimistic state survive Comment, Visit, Roulette and system-share round trips. Its Card footer exposes exactly three Restaurant actions—Record Visit, WantToGo and Roulette—while List remains available from its existing global and Restaurant Detail surfaces. This prevents double back buttons, duplicate route state and reload-driven session loss.

Deep links are parsed only for allowlisted `restaurant`, `profile`, `list`, and `activity` shapes, reject credentials/malformed identifiers, resolve to a typed route, and are handed to the declared owner. Production AASA/domain validation and public-link privacy remain separate native/backend release gates.

Completed Hybrid editors use optional `navigation.openHybrid` command metadata `replaceCurrent`; it is not part of route identity and is absent on ordinary push commands. Native replaces the current history entry and folds an adjacent identical destination, so a restored editor cannot remain behind its saved Restaurant Detail. Browser Back starts immediately; applying a Native Back response waits for that Web history traversal (bounded when no prior entry exists), retains the latest-intent guard, and cannot be overwritten by the same traversal's later `popstate`. Correlated bridge acknowledgements remain adapter-local and Native-origin events retain their authority. This changes neither route ownership nor the persistent WebView.

Secondary React pages share `PersistentPageNavigation` / `HybridBackButton` for their compact, scroll-persistent back chrome. The primitive owns the safe-area background and 44-point return target, but not navigation history or business state. Restaurant full-page consumers suppress the inner preview-card close; modal/card consumers retain their existing close. Browser document and nested overlay owners use the same primitive without introducing a second router. Native rollback keeps navigation chrome outside its `ScrollView`.

Native presentation chrome has one owner, independently of route/data ownership. `TasteMapHybridNativeNavigationPolicy` identifies existing self-navigating Profile Edit, Restaurant Edit, acquisition-native, Restaurant Add-to-List, and Premium Store destinations; the generic Native host does not add another `NavigationStack` or exit to them. Body-only settings/system destinations retain the host navigation. Self-navigating authorization/missing-data fallbacks supply their own single exit. Profile editor variants use `TasteMapReturnButton` / shared React `PageBackIconButton` through `ModalShell` instead of duplicate Back + Cancel; save, draft disposal, pending-save dismissal locks, List completion and Premium cleanup remain owned by existing destination logic. This is presentation de-duplication, not a route-owner migration or new bridge capability.

The Swift and TypeScript route registries are tested against the same ownership matrix. `HYBRID_INTEGRATED` means a route can run through the formal app target; it is not `HYBRID_PRIMARY`, and Release still launches current SwiftUI.

Route existence is deliberately independent from primary-navigation membership. The route registry can contain `add` and every other owned surface while the exact bottom navigation remains only `map → discovery → profile` (`地图 → 发现 → 我的`). Add Restaurant is a real Hybrid route, but its sole root primary entry is the Map-owned floating `添加餐厅` CTA. It is forbidden to infer or generate bottom tabs from all registered routes.

## 6. Auth session and bootstrap contract

Bootstrap order is deterministic:

1. resolve host adapter;
2. negotiate `runtime.info` and capabilities;
3. ask native `AuthSessionManager` to restore the current Keychain-backed session and read `auth.sessionStatus`;
4. if authenticated, load the current Profile;
5. render the requested ready route.

During restore, React remains in a bootstrap state instead of flashing signed-out UI. Sign in is initiated by the Hybrid UI but executed by the existing native Sign in with Apple/AuthSessionManager flow. Logout calls the existing revoke/local-session cleanup flow, ends the Premium session, resets the current Profile route and emits the safe signed-out state. Account changes rebuild bridge services using the active `tm_` owner and do not reuse a prior user's DTO cache.

React receives only `state`, Taste Map user ID and optional display name. Apple credentials, access/refresh tokens, authorization headers and Keychain values remain native-only. Keychain remains the single credential store.

The UI vocabulary is: `loading`, `success`, `empty`, `offline`, `recoverableError`, `fatalError`, `authRequired`, and `permissionRequired`. Local assets and current-user data are sufficient for integrated routes to boot without a UI server or network. The offline banner reflects system online state without changing data ownership.

Safe-area CSS uses `env(safe-area-inset-*)`; the host disables remote UI loading; touch interactions remain semantic HTML controls with accessible labels and sufficient hit areas.

## 7. Event channel, lifecycle and share handoff

2026-09-11: additive `premium.productsChanged` (empty payload) invalidates only
Premium price presentation after Native Storefront changes. It does not emit a
whole-app `data.changed` or alter entitlements. Native owns the in-memory Product
cache; the existing product DTO continues to pass through `displayPrice`.
Optional `premium.purchase.tappedAtMilliseconds` is bounded, diagnostic-only wall
clock input for tap-to-StoreKit-invocation timing; it grants no permission and
never affects purchase validation. No receipt/account token crosses the bridge.

`TasteMapNative.v1` events use a versioned envelope, monotonic sequence, typed event name and JSON-safe payload. The integrated runtime emits:

- `auth.changed` after sign-in/logout;
- `navigation.route` for ownership transitions;
- `deepLink.received` after canonical parsing;
- `shareExtension.received` for a normalized share fingerprint and target route;
- `app.lifecycle` for foreground, background, resume and memory warning.
- `location.changed` after a meaningful fresh Native location update.
- `map.viewport.changed` after MapKit settles a real pan/zoom or camera update.
- `map.restaurant.selected` after the user selects/deselects a Native Restaurant annotation.

Events queued before the Capacitor plugin attaches are delivered after attachment. Lifecycle resume never reloads React. Share Extension ingestion remains native: the existing normalized payload store is retained, the handoff opens the persistent Hybrid Add Restaurant route because that surface is `HYBRID_INTEGRATED`, and only a non-sensitive fingerprint/route state crosses the bridge. React requests normalized candidates through the typed acquisition service; it never receives an App Group path or unrestricted shared payload.

## 8. Persistent WebView

2026-09-09 account-restore correction: the Hybrid SwiftUI host keeps a stable
presentation identity while Native rollback retains its per-account root identity.
The runtime-owned UIKit controller must not be detached by a SwiftUI identity
replacement during asynchronous credential restoration. Account invalidation still
clears Native session/cache/navigation state and emits the existing `auth.changed`;
React immediately unmounts account content and clears transient selections, drafts
and navigation acknowledgements. Persistent records and mutation IDs are untouched.
This changes neither renderer defaults nor route ownership. See the 0902 recovery
report for physical-device display verification and the separate server-500 blocker.

`TasteMapHybridRuntime` owns one lazily created `TasteMapHybridBridgeViewController` for the lifetime of the app runtime. Native presentations do not recreate it, and returning to Hybrid restores the same controller and React state. Route changes and lifecycle events are messages, not WebView reloads. The controller identity is exposed internally for regression verification only.

The bridge controller also owns one persistent `TasteMapHybridMapSurfaceHost`. That host embeds the already-established SwiftUI `RestaurantMapView` / `MKMapView` presentation inside the persistent shell; it is not a second SwiftUI Map page and it never owns the page header, scopes, FilterBar, Add CTA, selection card, or bottom navigation. The host maps the React placeholder rectangle into controller coordinates, masks only the small React control rectangles and passes their hit tests back to the WebView. Hiding the Map for List or Restaurant Detail keeps the same MapKit instance alive, so center, zoom, bounds and annotation state survive the return path.

Native map presentation is jointly gated by the accepted Hybrid Map route and the latest React visibility request. The runtime assigns a surface revision on receipt, before asynchronous session work, and the host ignores superseded updates. A hide takes effect on receipt; React also sends it directly from the layout transition rather than deferring it to a geometry animation frame. Native route changes independently hide the overlay on every non-Map destination. Early Map geometry can be prepared while hidden and becomes visible after Map route acceptance, preserving startup and return ordering without reloading or remounting either renderer. The existing public bridge DTO and route ownership remain unchanged.

## 9. Browser parity

Browser and Capacitor reuse `ProfilePage`, `RestaurantPreviewCard`, `MyMapBrowsePage`, the canonical Restaurant Detail body, shared CSS/tokens, image policy and Web presentation models. Browser renders the map slot through `MapView.tsx` and its Web provider; iOS renders the same slot through the typed Native MapKit surface. This explicit engine exception does not permit the page chrome, content order, labels, filters, rating semantics, image priority or layout to fork.

Add Restaurant follows the same rule at component level: Browser `AddRestaurantModal` and Hybrid `HybridAddRestaurantPage` compose the canonical `TasteMapRestaurantAcquisitionScaffold`, Search/City fields, Nearby state, and candidate-result renderer. Their adapters may differ for Web provider access versus typed Native location/share handoff, but they do not maintain parallel form markup or platform-specific visual CSS. All WKWebView acquisition inputs are at least `16px`, preserving native focus scale without weakening the viewport accessibility contract.

Nearby's existing v1 `candidates` field carries the complete accepted, distance-ordered 3 km snapshot, not a first-page truncation. The shared acquisition renderer expands it in local batches of 12 without GPS, another provider request, or a search cursor. The snapshot is owner/latest-request scoped before candidate registration and its UI batches reset on refresh, location or owner invalidation. Native rollback keeps the same complete-snapshot/local-expansion semantics. This compatible clarification adds no bridge method, DTO key, route-owner change, or claim of exhaustive provider recall.

The latest map product contract shows Restaurant imagery without quantity numbers, count circles or numeric stack badges. City and street views retain individual Restaurants with natural overlap; wider-area groups retain a real member's Restaurant image, while exact-coordinate stacks expose their real member list. Browser and iOS retain different map engines while sharing these data and interaction semantics. Native MapKit keeps the annotation/hit frame fixed at `44 × 44pt` and scales only its centered visited inner circle from 28 points nearby to 24 points far away; including the existing 2-point white separation ring on both sides, its visible outer diameter is 28–32 points. Native selected emphasis adds only 2–4 points to the inner diameter and remains centered. Browser uses shared overall sizes of 32 px normal and 36 px selected on both mobile and desktop, without continuous diameter scaling. The whole normal marker, including its white ring, remains within roughly twice an ordinary nearby POI's visual size; rating/dashed rings and the neutral hairline remain, with weaker shadow. No free-slot displacement or bottom anchoring moves a circle away from its source coordinate.

Both engines keep distinct Restaurant coordinates independently visible through city/street scale (`≤0.8°` latitude span), allowing natural overlap. Only exact latitude/longitude matches share a stack/list; the earlier 50 m proximity rule is superseded. Above `0.8°`, wider-area grouping progressively increases its collision radius to the full value at `2.4°`. A group retains its highest-priority real member's Restaurant image at that member's coordinate, never a quantity number, and tap zooms toward members. An exact-coordinate stack opens its complete real member list via the typed `map.restaurant.groupSelected` Hybrid event or Native rollback list. Labels use `此处` wording: no mall identity is inferred from proximity. Higher scores appear in front: personal ordering and the stable source-coordinate anchor follow rating → visit count → stable Restaurant ID; recommendation rank only breaks equal-rating ties. Selection temporarily changes foreground order without changing the wider-area representative. Original member coordinates never change, grouping reverses when zooming in, and pure pan preserves data, images, totals and ordering. These thresholds are scale controls, not administrative-boundary data. The root annotation frame never participates in size animation; QA geometry measures the actual visible circle center and outer diameter. The current-user avatar location marker retains its separate pointer anchor and never participates in the Restaurant comparator. On Browser, a missing Web map SDK may degrade to the honest local neutral map shell. On iOS, a missing AMap Web credential is irrelevant: MapKit is the required formal engine, and a static Web fallback can never satisfy iOS pan/pinch acceptance.

Exact-coordinate stacks must render up to three genuine member visuals: the highest-priority front Restaurant plus at most two actual member-image/fallback layers, never empty outline plates or duplicated leader images. The front circle remains the geographic anchor; back layers use fixed local offsets `(-10, -8)` and `(8, -10)` within the composite, without changing independent annotation coordinates. Each layer consumes that member's canonical descriptor and ring semantics, and the complete member set remains accessible in the list. Asynchronous image completion must validate member/visual identity so reuse cannot show a previous stack's image.

The later 2026-09-05 pending-destination override adds 4 points to `想吃 / 推荐` diameter without altering the visited baseline: Native normal outer diameter 32–36 points and selected at most 40, inside the same 44-point annotation. Browser keeps visited CSS border-box sizes 32/36 px and pending sizes 36/40 px, using a fixed 44 px anchor and the unchanged white ring. Real back members share this status policy; GPS distance never shrinks pending markers. MapKit receives the deterministic order through distinct `zPriority` values and a selected priority, not competing writes to annotation-root `CALayer.zPosition`. Pan acceptance includes actual compositor ordering and stable member/image identity. No DTO, ownership, engine or primary-route change is involved.

`TasteMapBridgeProjection` is an anti-corruption layer for legacy Web presentation sentinels. It does not rewrite real user IDs in DTOs or native storage.

### 9.0.1 2026-09-05/06 overnight scope, sizing and acquisition corrections

These corrections do not change engines, route ownership, or the Native rollback boundary. `MyMapBrowsePage` owns independent visited/want/recommended query banks, shared with the List view of the same scope; Native rollback uses `PersonalRestaurantScopeQueries`. Switching scope restores its query without fitting the camera. An explicit filter/search change fits only when the matching current snapshot is accepted, and a later scope switch cancels an unapplied fit. Cache identity includes every supported advanced filter.

Near/approved regional marker dimensions above remain the baseline through `2.4°` latitude span. Beyond that, shared logarithmic progress to `80°` shrinks Native inner diameter 24→10 points (visible outer 28→14) and Browser CSS border-box diameter 32→14 px. Pending and selection emphasis taper to 1 point. Anchor frames and source coordinates remain fixed; the grouping baseline is separate from visual diameter. The rejected 35 m / 24 px five-image flower experiment is not retained. Different coordinates overlap naturally; only strict coordinate matches use real-image stacks.

Owner Profile summary composition shares compact 8 / 4 / 44 / 10 spacing and hit-target tokens across React Browser/Capacitor and Native owner previews. It does not change statistics calculations, typography or field order.

Restaurant acquisition accepts bounded shorthand/alias matches and resolves provider completions into real candidates before display. Text search uses a fresh accepted GPS fix only when it matches the selected city. An expired previously accepted fix triggers the existing bounded precise-location refresh; failure falls back to city/name search, never a stale or city-center GPS substitute. With no prior accepted location/authorization, text search does not start a permission wait. Nearby separately enforces full accuracy and merges the 500 m POI supplement before the existing 3 km cutoff/distance sort. Synthetic acquisition GPS is paired only with the explicit synthetic-provider test gate, not ordinary QA or iPhone search.

The v1 acquisition DTO adds optional `cursor` / `nextCursor` without changing existing callers. The UI treats the cursor as opaque; Native pages capture owner, query, city, accepted location, candidates and expiry. Native consumes each cursor once, clears pages on a new search, and checks owner plus generation after async work before registering candidates. Editing query/city invalidates old UI responses and next-page results. Browser uses provider pagination behind the same interface. Continued loading means more actually obtained/provider pages, not a promise of exhaustive chain-store coverage. Exact shop availability and physical iPhone position still require real-device verification.

### 9.1 Independent acceptance gates

One shared React/CSS tree prevents platform drift, but two hosts can still render the same incorrect product. Hybrid acceptance therefore reports seven independent gates:

1. `PRODUCT CONTRACT`: exact approved topology and semantics, independent of host parity;
2. `ONE REACT UI`: formal Browser and Capacitor hosts consume the same page/shared components rather than parallel layouts;
3. `CURRENT CAPABILITY PRESERVATION`: Native-pending capabilities keep their formal UI entry and use typed Native handoff;
4. `BROWSER ↔ CAPACITOR`: same component/CSS and equivalent rendering state;
5. `LAFAYETTE / CANONICAL REFERENCE`: controlling reference parity when applicable;
6. `FUNCTION / SEMANTIC`: interactions, data sources, states and return paths, including Native owner-scoped capability authority;
7. `NEGATIVE CONTRACT`: forbidden topology, duplicate pages, semantic substitutions, no-op actions and silent capability loss are absent.

An applicable failure keeps the surface out of `PASS`, even when the other gates pass. Objective topology is executable policy, not documentation alone. `hybrid/tests/HybridGlobalProductContract.test.ts` locks exact bottom-navigation count/order, the single Add primary entry, Map scopes, Discovery tabs, canonical Restaurant Detail ownership and negative patterns such as fabricated cluster counts, default marker separation, wrong Activity-rating semantics and paste-link primary acquisition. App Shell/navigation changes must run this suite.

Batch closure also performs a systemic source scan for platform-specific page forks, migration-state hiding (`readOnly`, `disabled`, `unavailable`, missing/no-op callbacks), route-to-tab generation and shared Browser/Capacitor errors. Permission-sensitive actions are emitted by typed Native capability DTOs; JavaScript does not infer ownership from a user ID string or visibility state.

### Food-list read/share boundary (2026-09-06, first stage)

The additive optional `listsRead` / `listShare` capabilities expose `lists.get` and `lists.createShareLink`. List Restaurant DTOs preserve the original optional coordinate and an optional `{ valueOutOfTen, source, sampleCount }` rating. The source is `viewer` only for that viewer's own Visit aggregate, or `public` only for a supplied public aggregate; the current List API has no public rating aggregate, so that missing value stays nil. Public detail uses the existing authenticated List API in pages of 50; Native/Browser keep owner/List/revision-scoped opaque continuation tokens, reject superseded responses, and invalidate unauthorized cached detail. The shared React detail merges real pages and retains the existing row information. Link creation reuses the formal public-sharing API with current-owner checks; only the returned validated opaque HTTPS URL reaches the system-share action.

This is not food-list Map integration or a route-status promotion. My Map's gate, viewport, coordinates and events are unchanged. The legacy Browser CRUD handoff and Native rollback food-list Map/rating/share differences remain separate open work; anonymous share landing pages retain their deliberately privacy-reduced summary contract.

### Analytics identity and shared-report boundary (2026-09-06)

The optional `profile.analyticsIdentity` bundle supplies explicit `ownerUserID` / `recordOwnerID` proof for the existing presentation sentinel. The shared dataset accepts that mapping only when the bundle belongs to the actual profile user; it then filters records by the proved record owner before making report-local copies. Real DTO user IDs and native storage are not rewritten, and missing or mismatched proof never broadly authorizes the `owner` sentinel.

Native reads the current owner's real DiningCompanion and RecommendationSource directories, including rename/delete revisions, and the existing `Visit.recommendationSourceID` association. Local IDs and existing remote aliases are stable identities; linked social-user IDs are not companion/source IDs. The projection is read-only: it adds no schema, API, Worker, synchronization or persistence write. Known-empty directories are `[]`; unavailable directories or association data are `null`. Browser supplies its real owner-scoped companion directory, but its current persisted Visit/DB model has no formal recommendation-source directory/link channel, so source analytics remain explicitly unavailable there. The lightweight bridge-core build also reports unavailable identity data rather than inventing model fixtures.

Companion/source models preserve the Native P4-B/C identity and sample safeguards while adding the shared report's detailed evidence. Formal ID associations take precedence; legacy names resolve only when a known association is ID-less and the owner directory has one unambiguous active match. Source attribution is determined from full history once per Restaurant, so a later revisit or period selection cannot reassign its origin. Selected companion/source summaries and Restaurant evidence use that exact selection; separately labelled comparison sections may retain all eligible entities. The shared dataset excludes deleted, orphaned, invalid-date and future records against one report clock; displayed dates use the selected/device time zone. Report privacy metadata keeps companion identity and spending out of default public-share projection. This is an additive data boundary, not a route promotion or proof of installed-device acceptance.

## 10. Build and Release policy

### Discovery city-search presentation boundary (2026-09-06, source integration)

All five shared Discovery tabs use `TasteMapCitySearch`: arbitrary city input is allowed, and loaded cities are suggestions, never an allow-list. NFKC/whitespace and optional `市` aliases normalize query labels only; stored Restaurant cities and GPS coordinates are untouched. Selecting a city requests `discovery.cityPage` for the current mode. It must not filter the first local `content.snapshot` batch and present that as a complete city search. Explicit reset returns to the unchanged default snapshot, and the selected city survives switching among the five tabs.

The React city-query controller is session-only. It immediately drops the previous selection, checks current authenticated ownership before and after requests, ignores superseded city/tab responses, and invalidates on authentication events. Continuation requires the same mode/city/window and paired opaque snapshot/cursor; returned items are cumulative. Failed append retains only the same owner's accepted page; failed replacement cannot resurrect an earlier city. Unknown engagement removes social count/actions rather than presenting fabricated zero counts. Query load/error/empty/retry/pagination states are explicit; client rating/sort filters are separate from the number of server results loaded.

The formal Browser adapter still reports `capability_unavailable` for city pages until authoritative authentication, city data and social interactions are connected together. The legacy Browser Community input is not proof of that capability. Native target/photo authorization and production server availability must be verified separately before claiming physical-device completion; these source changes do not stage/install the App or authorize deploying unrelated held Worker changes.

The production Hybrid bundle is created by `pnpm run hybrid:build`; the Debug evidence bundle by `pnpm run hybrid:build:debug`. Capacitor sync is followed by the deterministic local Swift-package configuration script because Capacitor regenerates its package manifest.

Mandatory Release properties:

- `webDir` points to local `dist`;
- no Capacitor `server.url`;
- no remote UI update system;
- no Debug fixture or fixture identity;
- no test auth header, development API URL, test route, source-machine path, token/secret marker or private key;
- no Premium/auth bypass;
- Release App resources and executable pass `hybrid:scan:release`.

The Phase 1 internal shell remains a diagnostic host. Phase 2A adds Capacitor 8.5.1 and the signed local bundle to the existing `com.lafayette.tastemap` target without changing Team, signing, Bundle ID, App Group, Sign in with Apple, Share Extension or other capabilities. Phase 2B adds a reproducible Debug-only staging command for fixed-Simulator evidence; the fixture and Debug default route are rejected by Release verification and restored out of the formal Release resources before commit/build. Debug can opt into `HYBRID_DEVELOPMENT` with `--tastemap-hybrid-development`; that mode and switch do not compile into Release. Release remains `NATIVE_PRIMARY` until Lafayette separately approves `HYBRID_PRIMARY`.

### Development companion app isolation

The shared Xcode scheme `TasteMap QA` builds configuration `DebugQA` as the independently installable companion app `味图测试`. Its bundle identifier is `com.lafayette.tastemap.qa`; its Share Extension uses `com.lafayette.tastemap.qa.ShareExtension`; and both targets use `group.com.lafayette.tastemap.qa`. The private app keeps `com.lafayette.tastemap` and `group.com.lafayette.tastemap`. Never reuse the private identifiers for QA installation: the separate application sandbox, default Keychain access group and App Group are what prevent test login, local data and pending share imports from overwriting or leaking into Lafayette's private app. `DebugQA` is development-only, starts with the isolated rich product fixture, uses the badged `AppIconQA` asset, and is not a Release/App Store configuration.

Physical-device private previews use the shared `Taste Map Private` scheme and `DebugPrivatePreview` configuration. That configuration preserves the private bundle identifier, App Group, official icon, Keychain session, SwiftData store and real network services, but fixes the root UI to the current Hybrid application. Plain `Debug` remains available for native regression testing and must never be used to overwrite the private phone installation. Neither private-preview nor QA installation may depend on a one-off launch argument to select the current UI.

## 11. Migration lifecycle

### Authorized Final Integration cutover — 2026-09-09

Lafayette's FINAL INTEGRATION execution approval supersedes the historical
Native-primary default for the new candidate. Release now selects HYBRID_PRIMARY
and the persistent shared React root; RootTabView remains the Native rollback.
Native MapKit and typed capability handoffs are unchanged. Ordinary Universal
Links are forwarded to the existing typed route parser; Referral remains closed.

The Internal candidate uses Release plus Configuration/ReleaseInternal.xcconfig:
TASTEMAP_INTERNAL_BUILD selects the existing Development account/API environment
only. It does not enable DEBUG, Visual QA, private-preview switches, fixture auth,
or Sandbox-only Premium UI. Ordinary Release retains its Production endpoint.
Both use signed local Web resources. This is source cutover authorization, not
evidence of a new real-device smoke, Final RC acceptance or TestFlight upload.

Each route advances independently:

`NATIVE_PRIMARY → HYBRID_POC → HYBRID_READY → HYBRID_INTEGRATED → HYBRID_PRIMARY → NATIVE_ROLLBACK → RETIRED_AFTER_MIGRATION`

`HYBRID_INTEGRATED` means the shared route, real native data/auth, formal app target, typed ownership/handoff and rollback path are connected and tested. It does not change the Release owner.

Moving to `HYBRID_PRIMARY` requires Lafayette's visual/product approval, automated parity and ownership coverage, fixed-Simulator and real-device smoke, performance acceptance, Release purity, and a tested rollback. Native code is not retired at the moment of the switch.

See `TASTEMAP_HYBRID_MIGRATION_STATUS.md` for the current route matrix.

## 12. Do not regress

- Do not create page-specific native plugins.
- Do not expose a general JavaScript-to-Swift selector.
- Do not make a remote Web URL the App Store UI runtime.
- Do not duplicate Browser and iOS React pages.
- Do not interpret One React UI as One Map Engine; Browser keeps its Web provider and iOS keeps Native MapKit.
- Do not make an AMap Web key/security code an iOS Hybrid or Release gate.
- Do not recreate MapKit inside Hybrid; reuse the canonical Native `RestaurantMapView` surface.
- Do not label an unavailable native capability as complete.
- Do not infer current-user ownership from an unscoped local query.
- Do not let Debug Visual QA, fixtures, routes, identities or Premium states enter Release.
- Do not change a route from native-primary merely because its bridge method exists.
- Do not remove current SwiftUI rollback code without separate approval.
- Do not create a new WebView per route or native handoff.
- Do not pass tokens, authorization headers or cloud-provider credential code into the formal Hybrid React bundle.
- Do not reintroduce marker quantity numbers, numeric stack badges, city/street proximity hiding, decorative aggregates, collision-avoidance offsets, free slots, bottom-anchored Restaurant circles, spiderfy/dispersion, platform-specific Map page forks or a second Map/List query state. Wider-area Restaurant-image groups split reversibly on zoom-in, and every exact-coordinate stack exposes its complete real Restaurant list.
- Do not let React resolve private native paths or independently change the canonical Restaurant image source identity.
- Do not begin a new route migration merely because Phase 2B infrastructure is ready.
- Do not equate route registration with bottom-tab membership or add Add Restaurant as a fourth tab.
- Do not infer Product correctness from Browser/Capacitor equality; Product Contract, visual reference, function and native data/security remain separate gates.


## Referral Reward extension — 2026-09-07

Settings now owns the additive detail route `settings/referrals` (`surface=settings, identifier=referrals`). Browser and Capacitor use `TasteMapReferralPage`, with the formal navigation stack handling the return path. Native-primary Settings has a matching `ReferralPremiumView`; the production root remains NATIVE_PRIMARY.

Additive bridge-v1 methods `referrals.dashboard` and `referrals.prepareRegistration` carry only explicit DTOs and an invitation code. Native owns session credentials, account-scope checks, temporary registration hints and Apple exchange. No token crosses into React. Browser does not gain a new Apple sign-in implementation in this task; an unavailable real session is an explicit auth-required state, not a fixture identity.

The Worker owns one-time registration attribution, five lifetime slots and a separate Premium Reward ledger. `referral_reward` is a fixed-term entitlement, projected by the existing authoritative service. Settlement runs on entitlement/dashboard reads and a five-minute scheduled handler; recorded Apple end time anchors queued rewards even if the next read is late. Successful Native sync refreshes authoritative Premium so the first valid Visit can unlock the reward without opening a paywall.

The temporary invitation hint is not an entitlement: it lives only in Native memory for at most 24 hours and clears after successful sign-in or logout. Failed/cancelled sign-in may be retried. Reopen the original link or re-enter its code after an app restart. No post-registration attribution or JavaScript credential storage is added.


## 2026-09-08 — First TestFlight Referral visibility hold
Lafayette defers the real two-account Referral E2E to internal beta follow-up. The first TestFlight hides Settings invitation entry and rejects direct invitation routes/registration preparation in Browser, Hybrid and Native rollback. Reuse the existing signed ProductionEnvironment.json product configuration, referralAvailable=false, without Debug/URL/local-storage overrides. Worker independently blocks invitation landing/dashboard and new-registration referral attribution; existing entitlements, qualification/settlement implementation, admin permissions, Offer mappings and inventory remain retained. No unverified invitation allocation or code consumption. This is release product visibility, not a new remote flag platform; reopening requires a reviewed config/build/deploy after real E2E PASS.
Core UI Settings rows and existing unavailable state remain canonical; Food/Dining visuals and page templates are unchanged. Do Not Regress: all entry paths, native bridge, stale saved invite code and server attribution must remain closed together. Normal StoreKit evidence remains PASS. Referral E2E is non-blocking only while this closure is effective. Real core smoke and visual/map approval still precede any HYBRID_PRIMARY cutover.

### 2026-09-08 current-city Discovery correction
The existing location.current DTO gains optional detectedCity, resolved by the
Native location service from the same authorized fix. The Native canonical
Discovery city uses this recent, owner-bound fix ahead of profile/history fallback.
React initializes default Discovery scope from it without overwriting a manual
selection. No new API, client geocoder, persistent location store or route promotion.

### 2026-09-09 Discovery read-cost candidate (local only)
The canonical content snapshot primes For You only. Same Taste and Trending use
their existing owner/city-bound page request when selected; no hidden-mode
prefetch or new shared cross-user TTL cache is introduced. Map still consumes the
same canonical For You snapshot. Candidate-first Worker reads and a single
Visit window ordering are local optimization candidates, not a deployment or
physical-device acceptance. See reports/DISCOVERY_D1_COST_OPTIMIZATION_20260909.md.
### 2026-09-10 — UGC safety capability boundary

Formal Hybrid now calls typed `community.safety`, `community.report`, `community.block`, and `community.deleteComment`. The authenticated, read-only `/api/v1/community/safety` projection reuses moderation visibility/ownership checks. Report and block retain the existing routes; own-comment delete retains the existing owner-authorized, idempotent DELETE/tombstone route.

UGC writes capture one in-memory authorization snapshot after normal session validation, then use scoped copies of the existing API clients. They never refresh a stale action under another account. Native checks owner and auth epoch after awaits; React ignores late results and clears hidden-content state on auth changes. No Sync mutation, ownership, or credential-storage contract changes.

Block invalidates only current-viewer public projections plus in-memory query/read caches, then emits `data.changed`. The renderer immediately filters matching authors and photo sources while reloading. Comment deletion remains retryable after an uncertain ACK because DELETE does not depend on a subsequent eligibility read of the tombstoned comment.

Integration prerequisite: deploy this commit's Worker changes under the separately authorized deployment workflow before shipping the updated client. No deployment or App Store RC is authorized by this module task.
