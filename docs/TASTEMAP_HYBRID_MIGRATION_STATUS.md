# Taste Map Hybrid Migration Status

Updated: 2026-09-02
Bridge: `TasteMapNative.v1`
Production default: `NATIVE_PRIMARY` (current SwiftUI application)

## Status definitions

| Status | Meaning |
| --- | --- |
| `NATIVE_PRIMARY` | Current SwiftUI/native route owns production behavior |
| `HYBRID_POC` | Isolated feasibility evidence only |
| `HYBRID_READY` | Shared React route, adapter, native DTO/service, tests and local shell are ready; no production switch |
| `HYBRID_INTEGRATED` | The route is connected to the formal Taste Map target, real native auth/data, typed ownership/handoff and persistent runtime; Release is still native-primary |
| `HYBRID_PRIMARY` | Explicitly approved production owner |
| `NATIVE_ROLLBACK` | Native route retained as tested rollback after a production switch |
| `RETIRED_AFTER_MIGRATION` | Native route may be removed only after separate approval and stability window |

## Route matrix

| Surface | Status | Phase 1 evidence | Production owner | Next gate |
| --- | --- | --- | --- | --- |
| My Map / My List | `NATIVE_PRIMARY` | Platform/native-navigation contract only | SwiftUI | Separate page migration and visual approval |
| Discovery / Community | `NATIVE_PRIMARY` | Platform/native-navigation contract only | SwiftUI | Separate data/interaction parity phase |
| Add Restaurant / Nearby | `NATIVE_PRIMARY` | Platform/native-navigation/location contracts only | SwiftUI | GPS/provider/write-flow migration phase |
| Profile / My | `HYBRID_INTEGRATED` | Shared `ProfilePage`, real AuthSessionManager/current-user DTO, formal signed local bundle, native/Hybrid handoff and Debug fixed-Simulator evidence | SwiftUI | Lafayette Product Acceptance, real-device smoke, performance acceptance and explicit `HYBRID_PRIMARY` approval |
| Restaurant Detail | `HYBRID_INTEGRATED` | Canonical React detail, stable Restaurant ID/DTO/image descriptor, formal route ownership, Native → Hybrid and Hybrid back regression | SwiftUI | Cross-entry Product Acceptance, real-device smoke and explicit `HYBRID_PRIMARY` approval |
| Visit editor | `NATIVE_PRIMARY` | v1 readiness contract reports `writeUIReady: false` | SwiftUI | Write DTO, validation, draft/save/error and attachment migration |
| Lists / Public Lists | `NATIVE_PRIMARY` | Native-navigation/deep-link shape only | SwiftUI | Separate route and data migration |
| Roulette | `NATIVE_PRIMARY` | Native-navigation contract only | SwiftUI | Separate approved-wheel migration |
| Analytics / Posters | `NATIVE_PRIMARY` | Native-navigation/share contracts only | SwiftUI | Separate high-fidelity Analysis renderer migration |
| Premium / Paywall | `NATIVE_PRIMARY` | Premium status contract only; unavailable in Phase 1 host | SwiftUI/StoreKit | StoreKit/entitlement bridge and Release verification |
| Settings / Data / Backup | `NATIVE_PRIMARY` | Native-navigation contract only | SwiftUI | Separate security-sensitive migration |

## Phase 2A completion boundary

Phase 2A embeds the signed local Capacitor/React runtime in the formal Taste Map target and connects Profile and Restaurant Detail to the existing native auth, owner-scoped data, typed navigation, deep-link/share/lifecycle event contracts and persistent WebView. Debug internal acceptance can opt into `HYBRID_DEVELOPMENT`; Release contains no such runtime mode or launch switch and continues to open the current SwiftUI application.

All other routes remain `NATIVE_PRIMARY` and are reached by typed handoff. Current SwiftUI Profile and Restaurant Detail remain intact as rollback. No Bundle ID, Team, capability, SwiftData schema, SyncEngine, Worker, D1, R2, StoreKit configuration or Production state is changed.

## Required update rule

Any commit that changes a surface's status must update this matrix and include the evidence that justifies the transition. Neither `HYBRID_READY` nor `HYBRID_INTEGRATED` may be promoted to `HYBRID_PRIMARY` without Lafayette's explicit approval. `NATIVE_ROLLBACK` or `RETIRED_AFTER_MIGRATION` cannot be inferred automatically.
