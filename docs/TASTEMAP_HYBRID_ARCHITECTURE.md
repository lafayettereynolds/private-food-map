# Taste Map Hybrid Architecture

Status: Phase 1 foundation approved for implementation; production route switch not approved.
Contract: `TasteMapNative.v1`
Updated: 2026-09-02

## 1. Architectural decision

Taste Map will converge on one React product UI that runs in two hosts:

- Browser: React → `TasteMapBrowserAdapter` → IndexedDB / existing Web services.
- iOS: the same React pages in a Capacitor `WKWebView` → `TasteMapNativeAdapter` → `TasteMapNative.v1` → native services and current-user SwiftData.

SwiftUI remains the production default and rollback implementation during incremental migration. Phase 1 does not switch the shipping app shell, remove SwiftUI pages, or migrate any page other than Profile and Restaurant Detail to `HYBRID_READY`.

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
| `src/hybrid/app/HybridAppShell.tsx` | Local app shell, bootstrap, online/offline state and route rendering |
| `src/hybrid/routes/HybridRouteRegistry.ts` | Route readiness, hashes, deep-link parser and ownership declaration |
| `ios/TasteMap/TasteMap/Hybrid/` | Native DTOs, current-user data service, dispatcher and Debug fixture |
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

Phase 1 defines contracts for:

- runtime and capability negotiation;
- auth status/sign-in/logout shapes (no token fields);
- current Profile;
- Restaurant get/list;
- Visit contract readiness;
- Sync status/run;
- haptics, share, location, photo picker, Premium status;
- navigation back to native-owned routes.

Only runtime, auth status, Profile read, Restaurant read, Visit contract negotiation and selection haptics are implemented by the internal Phase 1 host. Other methods return `capability_unavailable`; their contracts exist so later phases do not invent ad-hoc plugins.

## 4. Security and ownership boundary

- The bridge exposes neither Apple identity/authorization tokens nor session refresh tokens.
- Keychain remains native-only.
- SwiftData model instances never cross the bridge; the service creates lean, Codable DTOs.
- Native queries are scoped by the current Taste Map user ID through existing ownership predicates.
- Images cross as allowlisted descriptors (`nativeResource`, `publicOrCached`, `providerMerchant`, `foodDiningFallback`), not arbitrary filesystem paths.
- The selection policy remains: current user's real photo → legal public/cached photo → legal provider merchant photo → Food & Dining fallback.
- Error logs contain method, opaque request ID and duration only. They do not log payloads, tokens or user content.
- The Debug fixture is compiled under `#if DEBUG`, copied only by the Debug build script and absent from Release resources and binaries.

## 5. App shell and routing ownership

The Hybrid shell owns only its local hash navigation and the two `HYBRID_READY` page bodies. It supports:

- `#/profile`
- `#/restaurant/:id`

Profile → Restaurant pushes a hash history entry. Restaurant back uses Web history and returns to the same Profile state. Native-primary routes use `navigation.openNative` when the capability becomes available; the internal foundation host presents an explicit handoff state instead of pretending those pages were migrated.

Deep links are parsed only for allowlisted `restaurant`, `profile`, `list`, and `activity` shapes. Parsing never performs navigation or data access. Native entry ownership, universal-link validation and public-link privacy remain native/backend responsibilities until their route phase.

The fixed route registry is the auditable source of ownership. `HYBRID_READY` is readiness only; Release still launches current SwiftUI.

## 6. Bootstrap and state contract

Bootstrap order is deterministic:

1. resolve host adapter;
2. negotiate `runtime.info` and capabilities;
3. read `auth.sessionStatus`;
4. if authenticated, load the current Profile;
5. render the requested ready route.

The UI vocabulary is: `loading`, `success`, `empty`, `offline`, `recoverableError`, `fatalError`, `authRequired`, and `permissionRequired`. Phase 1 implements loading, success, offline, retryable fatal, and auth-required shell states. Local assets and current-user data are sufficient for the ready pages to boot without a UI server or network. The offline banner reflects system online state without changing data ownership.

Safe-area CSS uses `env(safe-area-inset-*)`; the host disables remote UI loading; touch interactions remain semantic HTML controls with accessible labels and sufficient hit areas.

## 7. Browser parity

Browser and Capacitor reuse `ProfilePage`, `RestaurantPreviewCard`, the canonical Restaurant Detail body, shared CSS/tokens, image policy and Web presentation models. The adapters are allowed to differ only in how DTOs are obtained. They are not allowed to fork content order, user-visible labels, rating semantics, image priority or layout.

`TasteMapBridgeProjection` is an anti-corruption layer for legacy Web presentation sentinels. It does not rewrite real user IDs in DTOs or native storage.

## 8. Build and Release policy

The production Hybrid bundle is created by `pnpm run hybrid:build`; the Debug evidence bundle by `pnpm run hybrid:build:debug`. Capacitor sync is followed by the deterministic local Swift-package configuration script because Capacitor regenerates its package manifest.

Mandatory Release properties:

- `webDir` points to local `dist`;
- no Capacitor `server.url`;
- no remote UI update system;
- no Debug fixture or fixture identity;
- no test auth header, development API URL, test route, source-machine path, token/secret marker or private key;
- no Premium/auth bypass;
- Release App resources and executable pass `hybrid:scan:release`.

The internal shell uses `com.lafayette.tastemap.hybrid.internal` and is not the shipping bundle. Formal integration into the existing signed Taste Map target is a later explicit migration step; Phase 1 does not alter Team, signing, capabilities, Bundle ID, Share Extension, or the shipping target.

## 9. Migration lifecycle

Each route advances independently:

`NATIVE_PRIMARY → HYBRID_POC → HYBRID_READY → HYBRID_PRIMARY → NATIVE_ROLLBACK → RETIRED_AFTER_MIGRATION`

Moving to `HYBRID_PRIMARY` requires Lafayette's visual/product approval, automated parity and ownership coverage, fixed-Simulator and real-device smoke, performance acceptance, Release purity, and a tested rollback. Native code is not retired at the moment of the switch.

See `TASTEMAP_HYBRID_MIGRATION_STATUS.md` for the current route matrix.

## 10. Do not regress

- Do not create page-specific native plugins.
- Do not expose a general JavaScript-to-Swift selector.
- Do not make a remote Web URL the App Store UI runtime.
- Do not duplicate Browser and iOS React pages.
- Do not label an unavailable native capability as complete.
- Do not infer current-user ownership from an unscoped local query.
- Do not let Debug Visual QA, fixtures, routes, identities or Premium states enter Release.
- Do not change a route from native-primary merely because its bridge method exists.
- Do not remove current SwiftUI rollback code without separate approval.
