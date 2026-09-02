# Taste Map Hybrid Migration Status

Updated: 2026-09-02
Bridge: `TasteMapNative.v1`
Production default: current SwiftUI application

## Status definitions

| Status | Meaning |
| --- | --- |
| `NATIVE_PRIMARY` | Current SwiftUI/native route owns production behavior |
| `HYBRID_POC` | Isolated feasibility evidence only |
| `HYBRID_READY` | Shared React route, adapter, native DTO/service, tests and local shell are ready; no production switch |
| `HYBRID_PRIMARY` | Explicitly approved production owner |
| `NATIVE_ROLLBACK` | Native route retained as tested rollback after a production switch |
| `RETIRED_AFTER_MIGRATION` | Native route may be removed only after separate approval and stability window |

## Route matrix

| Surface | Status | Phase 1 evidence | Production owner | Next gate |
| --- | --- | --- | --- | --- |
| My Map / My List | `NATIVE_PRIMARY` | Platform/native-navigation contract only | SwiftUI | Separate page migration and visual approval |
| Discovery / Community | `NATIVE_PRIMARY` | Platform/native-navigation contract only | SwiftUI | Separate data/interaction parity phase |
| Add Restaurant / Nearby | `NATIVE_PRIMARY` | Platform/native-navigation/location contracts only | SwiftUI | GPS/provider/write-flow migration phase |
| Profile / My | `HYBRID_READY` | Shared `ProfilePage`, native current-user DTO, Browser/native adapters, Debug Capacitor evidence | SwiftUI | Formal target integration, Product Acceptance, real-device smoke, explicit switch approval |
| Restaurant Detail | `HYBRID_READY` | Shared canonical `RestaurantPreviewCard`, native Restaurant DTO/image descriptor, local navigation and back behavior | SwiftUI | Cross-entry integration in formal target, Product Acceptance, real-device smoke, explicit switch approval |
| Visit editor | `NATIVE_PRIMARY` | v1 readiness contract reports `writeUIReady: false` | SwiftUI | Write DTO, validation, draft/save/error and attachment migration |
| Lists / Public Lists | `NATIVE_PRIMARY` | Native-navigation/deep-link shape only | SwiftUI | Separate route and data migration |
| Roulette | `NATIVE_PRIMARY` | Native-navigation contract only | SwiftUI | Separate approved-wheel migration |
| Analytics / Posters | `NATIVE_PRIMARY` | Native-navigation/share contracts only | SwiftUI | Separate high-fidelity Analysis renderer migration |
| Premium / Paywall | `NATIVE_PRIMARY` | Premium status contract only; unavailable in Phase 1 host | SwiftUI/StoreKit | StoreKit/entitlement bridge and Release verification |
| Settings / Data / Backup | `NATIVE_PRIMARY` | Native-navigation contract only | SwiftUI | Separate security-sensitive migration |

## Phase 1 completion boundary

Phase 1 establishes the architecture, local shell, route registry, build pipeline and typed bridge. Profile and Restaurant Detail may be exercised in the internal Debug Capacitor host with deterministic current-user data. The Release bundle proves local-asset and binary purity, but intentionally has no Debug fixture or fake authenticated session.

No current shipping route, Bundle ID, Team, capability, SwiftData schema, SyncEngine, Worker, D1, R2, StoreKit configuration or Production state is changed.

## Required update rule

Any commit that changes a surface's status must update this matrix and include the evidence that justifies the transition. `HYBRID_READY` may not be promoted to `HYBRID_PRIMARY` without Lafayette's explicit approval. `NATIVE_ROLLBACK` or `RETIRED_AFTER_MIGRATION` cannot be inferred automatically.
