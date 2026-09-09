# 0902 white-screen closure and Sync recovery checkpoint

Date: 2026-09-09, Asia/Shanghai. This is not Final RC or a cutover.

## Artifact

- HEAD: `9859b8cbc99e65984c8cfd935b2ec82a4e2be2a8` plus integrated uncommitted changes.
- Build: `2026090902`, Taste Map Private / DebugPrivatePreview.
- Source manifest SHA-256: `582be708a1427b6cda9ea2a2e82ed1d4bba7874a430530a5130efe810cc9644d`.
- Bundle: `com.lafayette.tastemap`; device iPhone 17 Pro Max / iOS 26.6.1.
- Actual runtime: HYBRID_DEVELOPMENT, referralAvailable=false; Development API unchanged.
- Signed app: `/tmp/tastemap-sync-white-fix.D3fAak/Build/Build/Products/DebugPrivatePreview-iphoneos/TasteMap.app`.
- Main and extension identity/provisioning PASS; dist/staged/bundled 26-file byte parity PASS.
- Installed 09:59; actual runtime identity captured at launch. No uninstall, store clearing or owner migration.

## White screen

0901 showed a SwiftUI representable host with no attached child controller/WebView,
including after a normal restart without a paused debugger. Native services kept
running. Account-scoped SwiftUI root replacement conflicted with the runtime-owned
persistent UIKit host. Preserve Hybrid host identity, retain Native account identity,
and clear Hybrid account presentation through the existing auth event instead.

The experimental wrapper/container repair failed verification and was removed.
Early remount test failures also included an offscreen-window layout issue; these
must not be represented as conclusive product red/green evidence. The final fixture
explicitly lays out UIKit, asserts mounting after restore and across account-state
changes, and separately verifies Native's per-account identity policy.

0902 real iPhone now displays Map, markers, Profile and Settings. Screenshots:
`/tmp/tastemap-sync-white-fix.D3fAak/map-restored-1001.png`, `retry-before-36.png`,
`retry-after-36.png`. White-screen closure PASS; this is not full map gesture,
account-switch, StoreKit or core-smoke acceptance.

## Data preservation and actual retry

Before and after overwrite: all 36 mutation IDs/fields and checked local entity
tables equal the original protected snapshot. Reauthenticated owner equals the
original Taste Map owner (private evidence only). Restaurant 28, Visit 25, Dish 5,
VisitDish 9, PhotoAsset 2, Profile 2, List 2, ListItem 2, Companion 6 preserved.
All six original/display/thumbnail files retain identical SHA-256 values.

Exactly one Settings retry tap at approximately 10:06:09 invoked the fixed
`sync.run -> retryNow()` path. It rearmed the original 36 failed mutations as queued,
without regenerating IDs. Ordinary automatic retry then ran; no second manual tap.

Development `/api/v1/auth/refresh` intermittently returned HTTP 500. Subsequently
one actual POST `/api/v1/sync/push` was observed at 10:07:31, batch size 1:

- Mutation: `3c69df3a-36ba-4883-9ee7-0bb83bd32640`, companion, baseVersion 1.
- Client request ID: `a382a3cd3dbacd17-AMS`; matching Worker CF-Ray: `a382a3cd3dbacd17`.
- HTTP 500, no acknowledgement, no conflict receipt observed.
- Follow-up exact-ID read of Development sync_mutation_receipts_v6 returned no row,
  with zero changes. This does not prove absence of every possible partial write.
- Server tail reported outcome ok / exceptionCount 0: this does NOT make HTTP 500 a success.
- Underlying server error text was intentionally not emitted by metadata-only diagnostics.
- Bounded read-only D1 schema check found users/auth_sessions/auth_refresh_token_history;
  no missing-table or quota cause is established by this evidence.

Final pending: 36 queued. First mutation stores retryable:http_500; another companion
stores retryable:AuthClientError; remaining IDs are preserved and unacknowledged.
Detailed per-mutation type/ID/error/dependency list:
`/tmp/tastemap-sync-white-fix.D3fAak/remaining-mutations.json`.
App process ended at 10:07:53 to prevent continued automatic calls to the failing
service. Final stopped snapshot preserves all checked business entity fields.
No queue purge or conflict winner was forced.

Five List nullable fields and three Visit version conflicts have source-level
regressions but were NOT reached by real Push. Parent List dependency ordering,
all-36 ACK coverage, pending zero, restart-zero, cloud parity and idempotency remain
unverified. SYNC REAL DEVICE = FAIL; Delete/account-switch smoke must not resume.

## Validation and boundaries

- Source suite: 1506/1506 PASS, including Worker and global Hybrid product contracts.
- TypeScript PASS.
- Native: 43 tests / 6 suites PASS (mount, diagnostic privacy, Apple lifecycle,
  local account isolation, coordinator, sync contracts).
- Signed generic Release build and capability audit PASS; SyncRecoveryDiagnostic
  and category=sync_wire absent from Release executable.
- Diagnostic logging is compiled only within existing Debug/Private Preview
  boundaries. It records wire field states/opaque IDs/status/ACK, not tokens,
  record bodies, photos, names or private notes. No auth/entitlement bypass.
- No Production/Worker deployment, DNS change, database mutation from CLI,
  renderer-default switch, Gift/Referral reward, TestFlight or Final RC.

Design System Compliance: existing shared React Core controls, Map/Profile/Settings
templates and Food/Restaurant imagery unchanged. Fix is host lifecycle and transient
account-state cleanup, not a new UI/template or visual redesign.

## Files changed in this white-screen turn

- ios/TasteMap/TasteMap/ContentView.swift — renderer-appropriate presentation identity.
- ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRootView.swift — inject the persistent controller into the same representable for testability; no wrapper remains.
- src/hybrid/app/HybridAppShell.tsx — clear transient account presentation on auth.changed.
- ios/TasteMap/TasteMap/Services/SyncAPIClient.swift — test-boundary, metadata-only wire evidence.
- ios/TasteMap/TasteMapTests/HybridControllerRemountTests.swift — UIKit mount and Native identity checks.
- ios/TasteMap/TasteMapTests/SyncRecoveryDiagnosticTests.swift — explicit-null metadata and privacy checks.
- hybrid/tests/HybridAccountPresentationReset.test.ts — account reset contract guard.
- docs/TASTEMAP_HYBRID_ARCHITECTURE.md — persistent host lifecycle clarification.
- reports/SYNC_RECOVERY_WHITE_SCREEN_2026090902.md — this checkpoint.

Unrelated pre-existing dirty hunks in those files remain preserved. No commit was created.
