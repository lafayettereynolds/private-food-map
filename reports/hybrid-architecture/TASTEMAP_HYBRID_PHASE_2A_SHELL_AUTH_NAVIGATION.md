# Taste Map Hybrid Migration Phase 2A — Shell / Auth / Navigation

Date: 2026-09-02  
Branch: `feature/hybrid-phase-2a-shell-auth-navigation`  
Baseline: `0eb58915ddc41ba0f64d81f39a1ec43d840962a3`  
Production access: **NO**

## Executive result

1. **Phase 2A: PASS.** The formal runtime, real native session boundary, typed navigation ownership, Native ↔ Hybrid handoff, deep-link/share/lifecycle contracts, persistent WebView and rollback path are connected and tested.
2. **Hybrid Shell integrated into the formal App architecture: YES.** The existing Taste Map target embeds Capacitor 8.5.1 plus a signed local React bundle and registers `TasteMapNative.v1` as a formal Capacitor plugin.
3. **Release default switched: NO.** Release has only `NATIVE_PRIMARY`; `HYBRID_DEVELOPMENT` and `--tastemap-hybrid-development` exist only under `#if DEBUG`.
4. **Real Auth integrated: YES.** Hybrid Sign in with Apple delegates to the existing native `AppleSignInService` / `AuthSessionManager` / Worker auth flow.
5. **Keychain remains the only credential store: YES.** No second Web credential store was introduced.
6. **React receives tokens: NO.** It receives only safe session state, Taste Map user ID and optional display name.
7. **Navigation ownership explicit: YES.** Current-user Profile and Restaurant Detail are Hybrid-owned; all unmigrated routes remain native-owned.
8. **Native → Hybrid works: YES.** Canonical Profile/Restaurant routes enter the persistent Hybrid controller.
9. **Hybrid → Native works: YES.** The E2E path Profile → existing native Roulette passes without migrating Roulette.
10. **Back behavior correct: YES.** Hybrid → Hybrid and Hybrid → Native → Hybrid paths return to the prior owner without double stacks or app exit.
11. **Deep-link contract works: YES.** Restaurant, public Profile, public List and shared Activity URL shapes are typed/allowlisted; malformed and unsupported routes fail closed. Production AASA is intentionally outside Phase 2A.
12. **Share Extension handoff contract works: YES.** Existing normalized native payload storage is retained; only a safe fingerprint and typed native Add Restaurant target cross the event channel.
13. **Persistent WebView established: YES.** One lazily created controller is owned by the app runtime; route/handoff/lifecycle changes do not reload it.
14. **Browser unharmed: YES.** Full TypeScript tests, typecheck and Vite production build pass; Browser adapters keep safe fallbacks.
15. **SwiftUI rollback intact: YES.** Current roots, Profile, Restaurant Detail and all native routes remain compiled and are still the Release owner.
16. **Release purity: CLEAN.** Archive scan found no Debug Hybrid switch/fixture, development URL, `server.url`, local path, secret or React credential surface.
17. **Can the next phase start Map migration?** The infrastructure is technically ready for a separately scoped Phase 2B, but this task **STOPS here**. Map remains `NATIVE_PRIMARY` and must not begin without Lafayette's explicit next instruction.

## Formal app-shell integration

The runtime chain is now:

```text
TasteMapApp / existing ModelContainer
  → TasteMapHybridRuntime
  → persistent TasteMapHybridBridgeViewController
  → signed local React HybridAppShell
  → TasteMapPlatform / TasteMapNative.v1
  → existing AuthSessionManager and owner-scoped SwiftData services
```

The main app target links the existing Capacitor Swift package at exact version `8.5.1`, embeds local `public/` assets and registers `TasteMapProductionNativePlugin`. No remote UI URL or remote update mechanism was added. The internal Phase 1 host remains available as diagnostic evidence; it is not the shipping app.

Runtime mode is deliberately asymmetric:

- Debug: `NATIVE_PRIMARY`, with explicit `--tastemap-hybrid-development` opt-in.
- Release: only `NATIVE_PRIMARY` is compiled.
- Future `HYBRID_PRIMARY`: not implemented and not inferred.

## Auth and session boundary

Bootstrap asks native code to restore the existing session before rendering authenticated content. A restoring state remains a loading surface, preventing a logged-out/authenticated flash.

Hybrid Apple sign-in invokes the existing native authorization UI and `NativeAuthServices`; successful authentication activates local account ownership and the existing Premium entitlement session. Logout uses the existing `AuthSessionManager.logout`, ends the local account and Premium session, resets the Hybrid route to current-user Profile and emits `auth.changed`.

The React session DTO contains only:

- `state`;
- Taste Map `tm_` user identity;
- optional display name.

It does not contain Apple identity/authorization tokens, access/refresh tokens, authorization headers, Keychain values or a fake transaction. The bridge constructs its data service from the currently restored owner on each request, so A → B → A does not reuse a prior account's service or DTO cache. Existing full-suite multi-account ownership tests remain green.

## Navigation ownership and handoff

The canonical typed route model is defined in Swift and TypeScript with the same surfaces, optional bounded identifiers and explicit owner. Arbitrary native class/view names cannot be opened from JavaScript.

| Route | Phase 2A owner | Behavior |
| --- | --- | --- |
| Current-user Profile | Hybrid | React route in persistent shell |
| Restaurant Detail | Hybrid | Stable Taste Map Restaurant ID; React route in persistent shell |
| Public Profile/List/Activity | Native | Typed external/deep-link handoff |
| Map, Discovery, Add, Visit, Lists, Roulette, Analytics, Premium, Settings | Native | Existing SwiftUI route, opened through typed handoff |

`TasteMapHybridNavigationCoordinator` holds one Hybrid history and at most one native presentation. `navigation.back()` dismisses the native presentation first, otherwise pops Hybrid history. The E2E verifies:

- Profile → Restaurant Detail → Profile;
- Profile → native Roulette → Profile.

The same WebView remains mounted during both paths.

## Event, deep-link, share and lifecycle contracts

Native → Web events use a versioned envelope and monotonic sequence. Phase 2A implements the foundation for:

- `auth.changed`;
- `navigation.route`;
- `deepLink.received`;
- `shareExtension.received`;
- `app.lifecycle` (`foreground`, `background`, `resume`, `memoryWarning`).

Events emitted before plugin attachment are queued, then delivered in order. Resume is an event, not a page reload.

The deep-link parser accepts only `https`/`tastemap` URLs with allowlisted Restaurant, Profile, List and Activity shapes; user/password URL components, missing Restaurant IDs and unsupported routes are rejected. This is local routing readiness, not a Production AASA deployment.

Share Extension remains native. Its existing normalized import is sent to the current native Add Restaurant route because Add Restaurant is still `NATIVE_PRIMARY`; React receives no raw credential or unrestricted filesystem path.

## Dedicated Hybrid bundle and release boundary

The formal Hybrid bundle now builds from `src/hybrid/main.tsx` through `hybrid/app/index.html`, rather than importing the full Browser entry. This prevents Browser-only Google Drive/photo-provider credential code from being linked into the signed Hybrid UI. Hybrid photo rendering uses a native-selected safe presentation resource and does not receive a cloud access token.

`hybrid:stage:formal` builds and verifies the dedicated bundle, then stages it under `ios/TasteMap/HybridRuntimeResources`. `hybrid:scan:formal-release` separately scans the whole archived app and signed Web files.

Final scan result:

> 36 app files and 10 signed Web files passed; no Debug switch/fixture, Development URL, local path, secret, or credential surface in React.

Formal Capacitor configuration has `webDir = public`, local assets and no `server.url`.

## Verification

### TypeScript / Browser

| Check | Result |
| --- | --- |
| Phase 2A platform + route tests | **8 / 8 PASS** |
| Full Vitest suite | **51 files / 351 tests PASS** |
| TypeScript typecheck | **PASS** |
| Browser Vite production build | **PASS** (only the pre-existing large-chunk warning) |
| Formal Hybrid staging/verification | **PASS** |

### Swift / iOS tests

| Check | Result |
| --- | --- |
| Swift bridge package | **4 / 4 PASS** |
| Phase 2A integration tests | **5 / 5 PASS** |
| Full iOS unit/integration suite | **636 / 636 PASS**, 65 suites |
| Fixed-simulator Phase 2A UI E2E | **1 / 1 PASS**, 20.142 s |

The integration suite covers typed ownership/validation, Hybrid/native back stack, allowlisted deep links, safe session/event encoding and normalized share handoff. Existing full tests cover session restore, logout/concurrent auth behavior and account isolation.

The first full iOS run correctly caught direct `ContentUnavailableView` use in a new Hybrid native fallback surface. It was replaced with the canonical shared `TasteMapEmptyState`; the complete suite then passed. Test expectations were not weakened.

### Builds and archive

| Artifact | Result |
| --- | --- |
| Debug iPhone 17 Pro Simulator | **PASS** |
| Release Simulator | **PASS** |
| Generic physical-device Release | **PASS** |
| Signed archive | **PASS** |
| Main App + Share Extension | **present and signed** |
| Archive release-purity scan | **CLEAN** |

Archive: `build/phase2a-archives/TasteMap-Hybrid-Phase2A.xcarchive`

The archive keeps the existing bundle ID `com.lafayette.tastemap`, Team `7G5J9MJX88`, Sign in with Apple and App Group `group.com.lafayette.tastemap`. It is a development-signed local archive (`get-task-allow = true`), was not uploaded, and does not claim App Store distribution readiness.

## Fixed Simulator evidence and performance observation

Device: iPhone 17 Pro, iOS 26.5, UDID `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`. It was not cloned or erased.

Screenshot: `reports/hybrid-architecture/screenshots/phase2a-hybrid-profile-final.png`

Observed Debug/Rich-fixture timings from the final UI E2E:

- `simctl launch` process acknowledgement: **0.66 s**;
- launch → WebView observed: **about 6.2 s** (includes XCTest automation setup and one-second polling granularity);
- launch → rich Profile observed: **about 7.3 s** under XCTest;
- Profile → Hybrid Restaurant observed: **about 1.5 s**;
- Hybrid Restaurant → Profile observed: **about 1.5 s**;
- Profile → native Roulette observed: **about 2.0 s**;
- native Roulette → persistent Profile observed: **about 2.2 s**.

These are E2E observation bounds, not internal production signposts; bridge initialization and session restore were not fabricated as separate measurements. The controller is lazily created once and its identity is stable across transitions.

After 32 seconds in the deterministic Rich Debug fixture, the Simulator reported approximately **485 MiB RSS for the app process plus 206 MiB for its WebContent process**. This is a high Debug-simulator observation and must be compared with a non-fixture real-device build before any `HYBRID_PRIMARY` decision. No route transition created a second WebContent process, so Phase 2A did not show the targeted per-route WebView recreation regression. No premature optimization was added in this architecture phase.

## Files and architecture changes

Major additions/updates:

- formal Capacitor host, runtime configuration, persistent runtime/root and navigation coordinator under `ios/TasteMap/TasteMap/Hybrid/`;
- existing app/root integration in `TasteMapApp.swift` and `ContentView.swift`;
- formal signed resources under `ios/TasteMap/HybridRuntimeResources/`;
- typed platform navigation/event contracts and Browser/native adapters;
- dedicated Hybrid entry and safe Hybrid photo presentation adapter;
- deterministic staging and formal Archive purity scan scripts;
- route/platform integration and UI E2E tests;
- Hybrid architecture and route migration status documentation.

Not changed:

- SwiftData schema;
- SyncEngine;
- Worker, D1, R2 or Production;
- StoreKit configuration;
- Team, Bundle IDs, capabilities or App Icon;
- Product visuals;
- any page migration beyond Profile and Restaurant Detail;
- current SwiftUI rollback implementations.

## Remaining gates

- Lafayette Product Acceptance of the integrated Profile and Restaurant Detail in the formal app host.
- Real-iPhone Hybrid development smoke: sign-in/session restore, Profile → Restaurant → Back, Profile → native route → Back, background/resume and account A → B → A.
- Non-fixture real-device cold-start and memory measurement before any primary switch.
- Production universal-link/AASA and public-link privacy validation in a later authorized release phase.
- Explicit Lafayette approval before adding `HYBRID_PRIMARY` or beginning Phase 2B Map migration.

## Stop condition

Phase 2A ends here. Map, Discovery, Add Restaurant and every other native-primary surface remain untouched and are not started automatically.
