# Frozen StoreKit reconciliation and first TestFlight preparation

## Normal StoreKit real device — PASS, preserved

The previous USER ACTION REQUIRED label incorrectly combined a completed normal purchase/restore loop with unfinished Referral and A→B→A gates. It was not supported by a demonstrated regression and is superseded.

Frozen actual evidence: STOREKIT_SANDBOX_E2E_2026-09-08.md, 15:39 active purchase and 15:47 real Restore sections; STOREKIT_REMAINING_GATES_2026-09-08.md; local build/storekit-sandbox-e2e/purchase-1539-evidence.json and restore-1547-evidence.json. This was iPhone17ProMax, ReleaseSandbox, actual Apple Sandbox, isolated Development API—not Simulator or unit tests.

Monthly/Annual product load, Monthly Sandbox purchase, transaction verification, authoritative server entitlement, UI Premium refresh and Restore Purchase are all PASS. Annual purchase and cross-account A→B→A are not inferred from this single-account evidence. No repeated purchase/restore is requested.

Reconciliation: last relevant semantic commit 4d5fe935ff8658644ef2ecf3cfc872b87a9fcc50 was at13:50, before the successful frozen device evidence. OCSP transport was corrected before the 15:39/15:47 acceptance. Production source e03f0495e4655235251e31e225f4c6852aefd978 preserves that transport contract. Current StoreKitMembershipPurchaseProvider.swift, PremiumEntitlementService.swift, worker/appStoreCommerceV1.ts and worker/appleSignedData.ts have no diff against e03f0495. Monthly/Annual IDs are unchanged. No later breaking purchase/verification/entitlement change was found that invalidates the seven frozen results. Evidence scope remains Development-backed; do not relabel it as a newly executed formal-Production purchase.

## Baseline and Referral follow-up

CURRENT PRODUCTION BASELINE remains dd0369b9-26c1-4fe7-a23b-9a56f5887661, ADOPTED / PASS. 87b45679 is the previous verified baseline / rollback reference. Core/regression/purity/Notifications/mapping/Production Sandbox-Offer isolation retain PASS. No Production deployment or rollback by this task.

User decision: no second Apple Account is required now. Referral A→B registration→first valid Visit→Invitee14D→Reward1, plus Reward2–5, are DEFERRED TO TESTFLIGHT INTERNAL BETA. Offer E2E becomes NON-BLOCKING FOR FIRST TESTFLIGHT only when release visibility is proven disabled. Do not delete model/API/ledger/entitlement/mapping, consume inventory or weaken Production sandbox_offer_forbidden.

## Concurrent implementation boundary

Another task began modifying the same checkout during inspection, including ProductionEnvironment.json, Referral UI/service, Worker registration/landing guards and staged assets. This task's attempted multi-file patch failed its expected-context validation; none of its proposed replacement policy was applied. Do not install a second policy or overwrite the other task's work.

Observed implementation uses signed ProductionEnvironment.json referralAvailable=false, shared React policy, Native resource read, hidden Settings entry, guarded direct page and invitation hint/dashboard, and source Worker guards. No user URL/storage/Debug override was observed. Backend source edits are not deployed evidence. Existing Production authentication/qualification/ownership/Sandbox isolation remains the boundary until an explicitly controlled later release; no source-only change is claimed live.

Independent test run at16:16:32: worker/referralAvailability.test.ts, src/hybrid/app/HybridRemainingUIContract.test.tsx and hybrid/tests/HybridGlobalProductContract.test.ts — 88/88 PASS. This is source/contract evidence only, not installed-runtime acceptance.

Artifact mismatch at16:17: existing formal build2026090801's ProductionEnvironment.json lacks referralAvailable and predates the new guards. Device inventory lists com.lafayette.tastemap build1 and QA906.27, not a newly verified closed-Referral formal artifact. Another task is also replacing staged hashed JS. Therefore REFERRAL FIRST-TESTFLIGHT VISIBILITY cannot yet be reported DISABLED for the installed/final artifact. Status: FAIL (artifact acceptance pending, not an observed failure of the source guard). A single build/install owner must finish stage→app byte parity→installed runtime before closing this gate.

No app installation, process termination, user data mutation or real smoke run was performed here. Existing Sync failure diagnostics already expose stage/category/status/duration/retry without user payloads; bridge diagnostics are method/request/duration-scoped. Actual log capture must attach to the final identified smoke artifact, not relaunch the current unidentified build or mix QA/Sandbox/Production sessions.

## One complete iPhone smoke run — after exact artifact installation

Record build, renderer (Native primary versus React Hybrid/Native MapKit), start/end time and each failed step. A Native rollback result must not be presented as Hybrid visual/performance acceptance. Use only user-created disposable test records for delete/retry tests. No purchase, restore, second Apple account or Offer redemption is required in this run.

1. Open Settings: confirm no Invite Friends entry or invite-code form. Open an existing invitation link and confirm no attribution form/hint; ordinary supported tastemap.cn public links must still work. Do not enter a real Offer code.
2. AUTH: Sign in with Apple; inspect current Taste Map userID locally; logout/login with the same identity and confirm the same owner and correct records. Do not send tokens or Apple credentials.
3. MAP: pan repeatedly, pinch in/out, select a marker, Detail→Back and compare viewport. Map→List→Map must retain context. Record obvious stalling, dead controls, incorrect page or damaged layout; screen recording helps correlate timing.
4. LOCATION: allow location and confirm real results. Change to deny in iOS Settings, verify honest denied state, then Settings→Allow and return; confirm recovery without fabricated location.
5. VISIT: create a disposable Visit, edit rating and dish, save, reopen and compare; delete that Visit, reopen Restaurant/history and verify absence.
6. PHOTO: on another disposable Visit use Camera and PhotosPicker, save/upload and inspect; go offline before another upload, confirm queued/failure state, reconnect/retry, inspect then delete the test photo. Do not delete unrelated photos or records.
7. SYNC: manual sync; offline create/edit of the test record, reconnect and sync; logout/login, confirm changes retained. Delete the test record, sync/relaunch/login and verify no resurrection.
8. SHARE EXTENSION: from Safari share a supported Restaurant link to Taste Map with the app closed, then repeat while open; confirm correct import destination and return state. Cancel drafts you do not want saved.
9. UNIVERSAL LINK: use an existing permitted tastemap.cn Restaurant/List/Activity link from Notes or Messages in cold and warm launch; check destination/back. Referral attribution is not part of this run.
10. VISUAL/MAP: separately report FINAL VISUAL and MAP GESTURE SMOOTHNESS PASS/FAIL. Focus only on broken layout, wrong page, dead control, severe stutter or visual corruption, not redesign/polish.

Return one consolidated result with failed step number, time and screenshot/recording. Codex owns correlation, sanitized log collection, diagnosis and scoped fixes. No raw codes/JWS/tokens in output. These instructions are a pending runbook, not test evidence.

## Cutover and Final RC

NORMAL STOREKIT REAL DEVICE: PASS.
REFERRAL FIRST-TESTFLIGHT VISIBILITY: FAIL (new artifact/runtime proof pending).
REFERRAL REAL E2E: DEFERRED TO TESTFLIGHT INTERNAL BETA.
REAL DEVICE CORE SMOKE: USER ACTION REQUIRED.
FINAL VISUAL: USER ACTION REQUIRED.
MAP GESTURE SMOOTHNESS: USER ACTION REQUIRED.
FINAL CUTOVER GATE: CLOSED.
HYBRID_PRIMARY: NOT YET.
FINAL RC: NOT YET.
TESTFLIGHT READINESS: NOT READY.

The Cutover predicate is baseline/core/purity/Notifications/mapping/normal StoreKit PASS + Referral visibility DISABLED + real core smoke/visual/Map smoothness PASS. Deferred Referral E2E itself is not a blocker once visibility passes.

Build2026090801 and all existing archives remain PRE-CUTOVER ONLY. After approved cutover retain SwiftUI rollback and generate a new clean Web→stage→HYBRID_PRIMARY Release→signed app→Archive; verify final behavior purity, staged/bundled parity, full suite, F1-C4, account isolation, Premium/Gift/Referral and Release endpoints. Only that new accepted Archive can become FINAL RC PASS. No new Batch3 or TestFlight upload is authorized by this report.

## Design System Compliance

Core UI: observed source reuses Settings rows and existing empty/back primitives, no new scale. Food/Dining: unaffected. Canonical template: only the explicitly authorized Referral entry/flow is held; unrelated hierarchy retained. No duplicate renderer/policy added by this task. Installed visual/default-SwiftUI regression and full consumer acceptance remain unverified, not PASS from tests alone.
