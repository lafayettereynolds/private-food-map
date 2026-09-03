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
| `src/components/MapView.tsx` | Browser-only Web map renderer, natural overlap and deterministic marker layering |
| `src/components/NativeMapSurface.tsx` | Thin React declaration of the iOS map rectangle, filtered marker presentation and React-control exclusions |
| `src/hybrid/routes/HybridRouteRegistry.ts` | Route readiness, hashes, deep-link parser and ownership declaration |
| `ios/TasteMap/TasteMap/Hybrid/TasteMapHybridMapSurface.swift` | Persistent MapKit adapter that reuses `RestaurantMapView`; it does not create a second `MKMapView` implementation |
| `ios/TasteMap/TasteMap/Hybrid/` | Native DTOs, current-user data service, dispatcher, navigation coordinator and persistent production host |
| `ios/TasteMap/HybridRuntimeResources/` | Signed local React bundle and Capacitor configuration embedded in the formal Taste Map target |
| `hybrid/capacitor-shell/` | Internal Capacitor host that consumes signed local `dist/` assets |
| `hybrid/scripts/` | Reproducible build, sync, Debug fixture installation and Release-purity checks |

## 3. `TasteMapNative.v1`

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

Phase 2A formally implements runtime/auth status, Sign in with Apple, logout, Profile read, Restaurant read, Visit contract negotiation, selection haptics, typed navigation and event delivery in the shipping target. Phase 2B adds `map.viewport`, `map.surface.update`, `map.viewport.changed`, `map.restaurant.selected`, `location.current`, and throttled `location.changed` delivery. `map.viewport` remains the owner-scoped data projection. `map.surface.update` is presentation-only: React sends the filtered marker DTOs, product-state descriptors, its viewport rectangle and small React-control exclusion rectangles; Native places the persistent MapKit surface and reports actual viewport/selection changes. It carries no credentials, persistence objects or write authority. Batch 2 adds typed owner-scoped Visit/Dish/photo writes, Restaurant acquisition, camera/photo-library input, StoreKit, Sync, permissions and data/account route actions without moving persistence, ownership, provider, entitlement or security policy into JavaScript. The viewport request carries bounds, zoom, scope, filters, sort/search state and an opaque request ID; the response contains lean owner-scoped marker/list DTOs and never serializes SwiftData entities. Native-owned high-risk workflows keep their established Native screens/services behind specific typed methods; unsupported operations return `capability_unavailable` rather than pretending to succeed.

## 4. Security and ownership boundary

- The bridge exposes neither Apple identity/authorization tokens nor session refresh tokens.
- Keychain remains native-only.
- SwiftData model instances never cross the bridge; the service creates lean, Codable DTOs.
- Native queries are scoped by the current Taste Map user ID through existing ownership predicates.
- Images cross as allowlisted descriptors (`nativeResource`, `publicOrCached`, `providerMerchant`, `foodDiningFallback`), not arbitrary filesystem paths. Local resources are read through the allowlisted `tastemap-resource://` scheme handler.
- The selection policy remains: current user's real photo → legal public/cached photo → legal provider merchant photo → Food & Dining fallback.
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

React is the navigation truth while a Hybrid-owned page is visible. `TasteMapHybridNavigationCoordinator` is the transition boundary, not a second business stack: it keeps one Hybrid history plus at most one native presentation. The contract exposes `navigation.openHybrid`, `navigation.openNative`, `navigation.back`, and `navigation.current`, all with validation and structured errors.

Profile → Restaurant and Map → Restaurant append one Hybrid history entry. Hybrid → Native presents an existing SwiftUI route without destroying the persistent WebView. Back dismisses that native presentation first; otherwise it pops Hybrid history. Native → Hybrid delivers the canonical route to the same long-lived shell. My Map / My List keeps one `MapBrowseState` containing mode, scope, filters, sort, city, search, viewport and selection; changing mode or returning from Restaurant Detail does not construct a second query state. This prevents double back buttons, duplicate route state and reload-driven session loss.

Deep links are parsed only for allowlisted `restaurant`, `profile`, `list`, and `activity` shapes, reject credentials/malformed identifiers, resolve to a typed route, and are handed to the declared owner. Production AASA/domain validation and public-link privacy remain separate native/backend release gates.

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

`TasteMapHybridRuntime` owns one lazily created `TasteMapHybridBridgeViewController` for the lifetime of the app runtime. Native presentations do not recreate it, and returning to Hybrid restores the same controller and React state. Route changes and lifecycle events are messages, not WebView reloads. The controller identity is exposed internally for regression verification only.

The bridge controller also owns one persistent `TasteMapHybridMapSurfaceHost`. That host embeds the already-established SwiftUI `RestaurantMapView` / `MKMapView` presentation inside the persistent shell; it is not a second SwiftUI Map page and it never owns the page header, scopes, FilterBar, Add CTA, selection card, or bottom navigation. The host maps the React placeholder rectangle into controller coordinates, masks only the small React control rectangles and passes their hit tests back to the WebView. Hiding the Map for List or Restaurant Detail keeps the same MapKit instance alive, so center, zoom, bounds and annotation state survive the return path.

## 9. Browser parity

Browser and Capacitor reuse `ProfilePage`, `RestaurantPreviewCard`, `MyMapBrowsePage`, the canonical Restaurant Detail body, shared CSS/tokens, image policy and Web presentation models. Browser renders the map slot through `MapView.tsx` and its Web provider; iOS renders the same slot through the typed Native MapKit surface. This explicit engine exception does not permit the page chrome, content order, labels, filters, rating semantics, image priority or layout to fork.

Add Restaurant follows the same rule at component level: Browser `AddRestaurantModal` and Hybrid `HybridAddRestaurantPage` compose the canonical `TasteMapRestaurantAcquisitionScaffold`, Search/City fields, Nearby state, and candidate-result renderer. Their adapters may differ for Web provider access versus typed Native location/share handoff, but they do not maintain parallel form markup or platform-specific visual CSS. All WKWebView acquisition inputs are at least `16px`, preserving native focus scale without weakening the viewport accessibility contract.

The map product contract forbids numeric or food-count clusters at every zoom level. Every Restaurant remains an independent marker. Normal layout uses natural overlap without default offset, dispersion or spiderfy. Layer priority is deterministic: selected Restaurant → rating → visit count → stable Restaurant ID. The current-user avatar location marker is a separate layer and never participates in the Restaurant comparator. On Browser, a missing Web map SDK may degrade to the honest local neutral map shell. On iOS, a missing AMap Web credential is irrelevant: MapKit is the required formal engine, and a static Web fallback can never satisfy iOS pan/pinch acceptance.

`TasteMapBridgeProjection` is an anti-corruption layer for legacy Web presentation sentinels. It does not rewrite real user IDs in DTOs or native storage.

### 9.1 Independent acceptance gates

One shared React/CSS tree prevents platform drift, but two hosts can still render the same incorrect product. Hybrid acceptance therefore reports seven independent gates:

1. `PRODUCT CONTRACT`: exact approved topology and semantics, independent of host parity;
2. `ONE REACT UI`: formal Browser and Capacitor hosts consume the same page/shared components rather than parallel layouts;
3. `CURRENT CAPABILITY PRESERVATION`: Native-pending capabilities keep their formal UI entry and use typed Native handoff;
4. `BROWSER ↔ CAPACITOR`: same component/CSS and equivalent rendering state;
5. `LAFAYETTE / CANONICAL REFERENCE`: controlling reference parity when applicable;
6. `FUNCTION / SEMANTIC`: interactions, data sources, states and return paths, including Native owner-scoped capability authority;
7. `NEGATIVE CONTRACT`: forbidden topology, duplicate pages, semantic substitutions, no-op actions and silent capability loss are absent.

An applicable failure keeps the surface out of `PASS`, even when the other gates pass. Objective topology is executable policy, not documentation alone. `hybrid/tests/HybridGlobalProductContract.test.ts` locks exact bottom-navigation count/order, the single Add primary entry, Map scopes, Discovery tabs, canonical Restaurant Detail ownership and negative patterns such as clusters, default marker separation, wrong Activity-rating semantics and paste-link primary acquisition. App Shell/navigation changes must run this suite.

Batch closure also performs a systemic source scan for platform-specific page forks, migration-state hiding (`readOnly`, `disabled`, `unavailable`, missing/no-op callbacks), route-to-tab generation and shared Browser/Capacitor errors. Permission-sensitive actions are emitted by typed Native capability DTOs; JavaScript does not infer ownership from a user ID string or visibility state.

## 10. Build and Release policy

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

## 11. Migration lifecycle

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
- Do not reintroduce clusters, default offset/spiderfy/dispersion, platform-specific Map page forks or a second Map/List query state.
- Do not let React resolve private native paths or independently change the canonical Restaurant image source identity.
- Do not begin a new route migration merely because Phase 2B infrastructure is ready.
- Do not equate route registration with bottom-tab membership or add Add Restaurant as a fourth tab.
- Do not infer Product correctness from Browser/Capacitor equality; Product Contract, visual reference, function and native data/security remain separate gates.
