# Taste Map Hybrid Migration Status

Updated: 2026-09-03
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
| My Map / My List | `HYBRID_INTEGRATED` — **REAL MAP INTERACTION BLOCKED** | Shared `MyMapBrowsePage`/`MapView`, owner-scoped `map.viewport`, Native location/avatar, canonical image descriptors and shared state are integrated. The current fixed-Simulator surface is the non-interactive static fallback, not `AMap.Map`. | SwiftUI | **Blocking before Batch 3:** Development Web（JS API）key/security code, live tile SDK load, pan/pinch/center/zoom/bounds acceptance, Lafayette Product Acceptance, real-device smoke and explicit `HYBRID_PRIMARY` approval |
| Discovery / Community | `HYBRID_INTEGRATED` | One shared five-tab React UI, shared Activity Card/FilterBar, Visit-rating semantics, owner-safe action adapters and exact/negative Product contracts | SwiftUI | Lafayette visual review, real-device interaction smoke and explicit `HYBRID_PRIMARY` approval |
| Add Restaurant / Nearby | `HYBRID_INTEGRATED` | One shared React Search/Nearby/Share/Manual UI; typed native provider, fresh GPS, distance, dedupe and Share Extension bridge; canonical Hybrid Restaurant Detail transition; fixed-Simulator evidence | SwiftUI | Real-iPhone Location/provider/Share smoke, Lafayette Product Acceptance and explicit `HYBRID_PRIMARY` approval |
| Profile / My | `HYBRID_INTEGRATED` | Shared `ProfilePage`, real AuthSessionManager/current-user DTO, formal signed local bundle, native/Hybrid handoff and Debug fixed-Simulator evidence | SwiftUI | Lafayette Product Acceptance, real-device smoke, performance acceptance and explicit `HYBRID_PRIMARY` approval |
| Restaurant Detail | `HYBRID_INTEGRATED` | Canonical React detail, stable Restaurant ID/DTO/image descriptor, formal route ownership, Native → Hybrid and Hybrid back regression | SwiftUI | Cross-entry Product Acceptance, real-device smoke and explicit `HYBRID_PRIMARY` approval |
| Visit editor | `HYBRID_INTEGRATED` | One shared React editor; typed Visit/Dish/photo draft DTOs; owner-scoped `LocalVisitRecordingStore`; existing mutation queue; native PhotosUI picker and `PhotoTransferCoordinator`; edit/create/delete handoff and automatic detail refresh; formal Release purity scan | SwiftUI | Lafayette Product Acceptance, real-device photo/camera-library smoke and explicit `HYBRID_PRIMARY` approval |
| Lists / Public Lists | `HYBRID_INTEGRATED` | Shared React list renderer, canonical Restaurant navigation and existing Native list-manage handoff | SwiftUI | Lafayette visual review, mutation smoke and explicit `HYBRID_PRIMARY` approval |
| Roulette | `HYBRID_INTEGRATED` | Shared approved wheel, current candidates and canonical Restaurant transition | SwiftUI | Lafayette visual review and explicit `HYBRID_PRIMARY` approval |
| Analytics / Posters | `HYBRID_INTEGRATED` | Shared five-mode infographic family, five real 9:16 poster renderers and typed system share | SwiftUI | Lafayette visual review, real-device share smoke and explicit `HYBRID_PRIMARY` approval |
| Premium / Paywall | `HYBRID_INTEGRATED` | Shared paywall; typed StoreKit product/purchase/restore/manage bridge; server-backed entitlement state remains authoritative | SwiftUI/StoreKit | Real App Store Connect Product IDs, Sandbox/TestFlight verification and explicit `HYBRID_PRIMARY` approval |
| Settings / Data / Backup | `HYBRID_INTEGRATED` | Shared Settings IA; real Sync status/run; live permission status; typed Backup/Import and Account Delete native routes; no fake legal/product/account state | SwiftUI | Real-device settings smoke, legal/external Release gates and explicit `HYBRID_PRIMARY` approval |

## Batch 2 completion boundary

Phase 2A embeds the signed local Capacitor/React runtime in the formal Taste Map target and connects Profile and Restaurant Detail to existing native auth, owner-scoped data, typed navigation, deep-link/share/lifecycle event contracts and a persistent WebView. Phase 2B adds My Map / My List. Batch 1 integrates the remaining Product UI through shared React components and exact Product/negative contracts. Batch 2 closes the typed Native capability boundary for Visit/Dish writes, photo library and camera capture, local originals/upload retry/delete, fresh-GPS Restaurant acquisition, Share Extension ingestion, StoreKit, Sync, permissions, Backup/Import, Account Delete entry and system actions.

Every integrated route still has production owner SwiftUI. Debug internal acceptance can opt into `HYBRID_DEVELOPMENT`; Release contains no such runtime mode or launch switch and continues to open the current SwiftUI application. Existing SwiftData, mutation queue, SyncEngine, Auth/Keychain, PhotoTransferCoordinator, StoreKit entitlement, Backup/Import and Account Delete services remain authoritative. Current SwiftUI surfaces remain intact as rollback. No Bundle ID, Team, SwiftData schema, Worker, D1, R2, real StoreKit product configuration or Production state changed.

The My Map route's integrated shell/DTO status does not constitute real-map
interaction acceptance. An offline/fallback screenshot cannot satisfy pan, pinch,
center, zoom or bounds gates. Batch 3 remains blocked until the Development AMap
credential is supplied outside Git and the fixed-Simulator live gesture protocol
passes.

## Required update rule

Any commit that changes a surface's status must update this matrix and include the evidence that justifies the transition. Neither `HYBRID_READY` nor `HYBRID_INTEGRATED` may be promoted to `HYBRID_PRIMARY` without Lafayette's explicit approval. `NATIVE_ROLLBACK` or `RETIRED_AFTER_MIGRATION` cannot be inferred automatically.
