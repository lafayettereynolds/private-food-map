# Taste Map｜Hybrid Batch 2 Native Capability Closure

> **SUPERSEDED iOS MAP GATE (2026-09-03):** The Development AMap credential
> blocker recorded below resulted from treating One React UI as One Map Engine.
> iOS now uses the persistent reused Native MapKit surface; Browser keeps its Web
> provider. AMap Web credentials are not an iOS or Release gate. See
> `mapkit-surface/TASTEMAP_HYBRID_MAPKIT_INTEGRATION.md` for the active result.

Date: 2026-09-03
Branch: `feature/hybrid-remaining-ui-batch`
Production owner: SwiftUI (`NATIVE_PRIMARY`)
Batch 3: **NOT STARTED**

> 2026-09-03 map-gate correction: Batch 2 capability code is complete, but the
> fixed Simulator is currently rendering the non-interactive static map fallback.
> `REAL AMAP INTERACTION = BLOCKED BY DEVELOPMENT AMAP CREDENTIAL`. Batch 3 must
> remain not started until live AMap pan, pinch zoom and viewport mutation pass.

## Outcome

Batch 2 closes the remaining React → `TasteMapNative.v1` → existing Native service boundaries needed by the integrated Hybrid Product UI. JavaScript does not own SwiftData, authentication, Keychain, photo files, synchronization, StoreKit entitlement, location/provider policy, Backup/Import transactions or destructive account behavior.

```text
Shared React Product UI
    → typed TasteMapPlatform method
    → TasteMapNative.v1 envelope
    → TasteMapHybridRuntime / specific Native route
    → existing owner-scoped service
```

Release still launches `NATIVE_PRIMARY`. `HYBRID_PRIMARY` was not enabled, SwiftUI rollback was not removed, and Production was not accessed.

## Capability closure

| Capability | Hybrid contract | Authoritative implementation | Result |
| --- | --- | --- | --- |
| Visit create/edit/delete | `visit.save`, `visit.delete` | `LocalVisitRecordingStore`, current owner and mutation queue | PASS |
| Dish / VisitDish | typed Dish drafts inside Visit transaction | existing Visit/Dish transaction and SwiftData relations | PASS |
| Photo Library | `photo.pick` | `PHPickerViewController` → `PhotoImportService` → `PhotoTransferCoordinator` | PASS |
| Camera | `photo.capture` | explicit camera permission + `UIImagePickerController` → same photo pipeline | PASS; real iPhone smoke pending |
| Photo original/upload/retry/delete | opaque `photoID`, `photo.discard`, `photo.retry` | owner-scoped local files, `PhotoAsset`, upload queue | PASS |
| Native GPS / Nearby | `location.current`, `acquisition.nearby` | fresh `CLLocation`, accuracy/staleness policy, provider search and distance sort | PASS; real iPhone/provider smoke pending |
| Search / Share / Manual acquisition | `acquisition.search/shared/manual/select` | existing provider/parser/dedupe/persistence services | PASS |
| Share Extension | `shareExtension.received` + `acquisition.shared` | existing App Group ingestion and normalized import store | PASS; real-device extension smoke pending |
| StoreKit | `premium.products/purchase/restore/manage` | `PremiumEntitlementService` and configured products provider | PASS; App Store Connect/Sandbox gate remains |
| Sync | `sync.status`, `sync.run` | existing `SyncCoordinator` | PASS |
| Backup / Import | `backup.openExport`, `backup.openImport` | existing `DataBackupSettingsView` and formal Export/Import services | PASS through typed Native route |
| Permissions | `permissions.status`, `permissions.openSettings` | live `SettingsPermissionSnapshot` and system Settings | PASS |
| Account / Delete boundary | `account.openDelete` | existing authenticated `AccountDeletionView`; runtime session cleared only after completion | PASS; no real account deleted |
| Haptics / system share | `haptics.selection`, `share.open` | existing native feedback/share sheet | PASS |

## Security and data boundaries

- Native derives current ownership from `NativeAuthServices.localAccountScope`; React never supplies `ownerUserID`.
- Keychain credentials, Apple tokens, access/refresh tokens and authorization headers never cross the bridge.
- Visit/Dish writes retain the current mutation queue and Sync semantics.
- Photo bytes and absolute file paths do not cross into React; only allowlisted `tastemap-resource://` previews and opaque IDs do.
- Camera and photo-library drafts use one existing local-original/upload/retry/delete pipeline.
- StoreKit Product IDs/prices come only from the configured products provider; missing products remain unavailable and no fake price or purchase success is rendered.
- Backup/Import and Account Delete keep their existing high-risk confirmation/transaction screens; Hybrid only requests the specific typed route.
- No SwiftData schema, Worker, D1, R2, SyncEngine, auth refresh, Production configuration or real account data was changed.

## Regression evidence

- Batch 1 systemic scan: 63 root-cause/contract families found and fixed; 0 objective P0/P1 Product/architecture regressions remain.
- Focused iOS capability regression: 167 tests / 16 suites passed.
- F1-C4 exact regression passed: Legacy v4 first import → manual cross-provider Restaurant merge → Visit re-resolution → second identical import `exactDuplicate` → no second Visit/no extra mutation. No real user file was imported twice.
- StoreKit local configuration emitted simulator framework diagnostics but all commerce tests passed; real product/Sandbox configuration remains an external gate.

## Final combined verification

All entries below were run from the same final Batch 2 working tree after Camera and permission-status closure.

| Gate | Result |
| --- | --- |
| TypeScript / React / Worker tests | PASS — 56 files, 391 tests |
| TypeScript + Worker typecheck | PASS |
| Browser Vite production build | PASS |
| Focused iOS Native capability suite | PASS — 16 suites, 167 tests |
| Full iOS unit/integration suite | PASS — 65 suites, 639 tests |
| Final Camera/Permissions focused iOS regression | PASS |
| Relevant Hybrid UI E2E | PASS — 3/3, including owned Visit edit → Hybrid editor → save → automatic Restaurant Detail refresh |
| F1-C4 exact duplicate Visit regression | PASS — no second Visit, no extra mutation |
| Debug Simulator build | PASS |
| Release Simulator build | PASS |
| Generic iOS Device Release build | PASS |
| Release Simulator purity scan | PASS — 38 app files, 16 signed Web files |
| Generic Device formal Release purity scan | PASS — 36 app files, 16 signed Web files |
| Production access / mutation | NONE |

The fixed Simulator preview remains a Debug Rich Demo / Premium Active session on the Hybrid Settings page. Its visual evidence is stored at `reports/hybrid-architecture/screenshots/batch-02/settings-system-capabilities.png`.

## Manual gates retained

1. **Blocking before Batch 3:** inject a Development-only AMap Web（JS API）key/security code, then pass live pan/pinch/center/zoom/bounds and viewport restoration on the fixed Simulator.
2. Lafayette visual review of remaining subjective spacing/composition in Batch 1 pages.
3. Real-iPhone camera, Photos limited/denied, local-original, upload retry/delete smoke.
4. Real-iPhone fresh GPS/Nearby/provider and Share Extension smoke.
5. App Store Connect Product IDs/subscription setup plus Sandbox/TestFlight StoreKit verification.
6. Non-destructive real-device Backup Export/Import navigation smoke; no second destructive real-user import.
7. Account Delete may be tested only with an authorized disposable account; no real account deletion was performed.
8. Production, TestFlight, App Store submission and `HYBRID_PRIMARY` remain outside this batch.

## Stop boundary

Batch 2 ends here. Batch 3, `HYBRID_PRIMARY`, Final RC, main merge, Production, TestFlight, App Store operations, Distribution signing changes, Production D1/R2, formal StoreKit setup, Production AASA and SwiftUI rollback removal were not started.
