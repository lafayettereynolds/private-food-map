# Unique physical-device acceptance — build 2026090802

## Superseding device-ownership handoff

Received a takeover notice from task3 (01a07a1a-da83-7160-af8f-2499204f5a04) during final log preparation. To avoid concurrent device replacement this task stopped its xcodebuild and host console collector, paused Console streaming, and sent the exact evidence boundary to task3. No subsequent installation or launch by this task. The unfinished persistent-log implementation is retained in source, not misrepresented as installed.

Last actual installed/started build:2026090802, NATIVE_PRIMARY, com.lafayette.tastemap. Actual source fingerprint5387510acec270ab4041c0a7c547dfd71b385f46e21bf5a76d4929db344ac5d9, HEAD4d5fe935ff8658644ef2ecf3cfc872b87a9fcc50 plus uncommitted changes. At16:48:00 local the device console printed the exact build/commit/fingerprint, renderer=NATIVE_PRIMARY and referralAvailable=false. Final installed executable SHA-25661df06c0b93ae9073c58f1b66326b2aacd43133a778910510dc787157d40f357. Installation container8D77A02E-E1E2-43A1-873F-38D1ADC003E7. Signature/purity and26 staged/bundled hashes PASS before that installation.

Later source fingerprint02a1e59162918f5abe030f79097754ab1a0f2f33d00df8998b2abaf511f0d38a adds persistent cold-launch logs; its build was interrupted and was NOT installed. Build path below may contain unfinished rebuild output and must NOT be reused as a frozen accepted artifact. Earlier source fingerprints below are preparation history, superseded by this exact installed identity.

Actual diagnostics: .private/device-smoke-2026090802/events-2026-09-08T08-48-00.658Z.jsonl, with the corresponding console log in the same private directory. No complete system logarchive was collected: log collect requires root, and noninteractive elevation was unavailable. Startup share/sync/entitlement events were captured; entitlement refresh_failed was observed before user login acceptance and is not a successful online entitlement check or proof invalidating frozen StoreKit purchase evidence. No full physical core/visual/Map/Referral-entry test was performed by this task.

NORMAL STOREKIT remains PASS. Referral real E2E deferred. Source Referral policy verification PASS, but REFERRAL FIRST-TESTFLIGHT VISIBILITY / CORE SMOKE / VISUAL / MAP remain unaccepted on device. Cutover CLOSED, Hybrid primary NOT YET, Final RC NOT YET. This report does not authorize task3's renderer selection or claim its artifact status; it only records the received handoff and this task's actual actions.

## Ownership and frozen scope

This task owns the sole build/install/log capture. The other task is evidence-review only. User explicitly selected formal Release / NATIVE_PRIMARY; no Hybrid preview or primary cutover. NORMAL STOREKIT REAL DEVICE stays PASS using the frozen actual seven checks. No new purchase, Restore, second Apple Account or Sandbox Offer redemption is required.

Production baseline stays dd0369b9-26c1-4fe7-a23b-9a56f5887661. No Production deployment, D1/R2 change or inventory allocation occurs here. Referral real E2E is deferred to internal beta, conditional on first-TestFlight consumer visibility being closed.

## Build identity

- Git HEAD: 4d5fe935ff8658644ef2ecf3cfc872b87a9fcc50, plus current uncommitted integrated source. This is not a clean commit-only build.
- SHA-256 build-input fingerprint: 2aecaa17467b8bb0f838580d0bd1f8b9374de4d749527a07a917cf741e7ee22a (1021 source/config/resource inputs).
- Build: 2026090802; version1.0; Bundle ID com.lafayette.tastemap.
- Renderer: NATIVE_PRIMARY; Hybrid renderer NO, by explicit user choice. Bundled Hybrid pages are not proof of an active Hybrid renderer.
- API: https://api.tastemap.cn; no origin fallback.
- Web index SHA-256: fee7ef3f438f96a97d892a32132806fded7fea4eb151c72c9ae2d446898d35ab.
- App target: /Users/lafayette/Projects/private-food-map-hybrid-final-integration/build/UniqueDeviceSmoke2026090802/Build/Products/Release-iphoneos/TasteMap.app.
- Device: connected iPhone17ProMax, CoreDevice60BBB934-D441-53FB-B8CF-0E3DB5878C4D, iOS26.6.1. Do not substitute the older paired iPhone12 or QA app.

The signed Info.plist carries TasteMapSourceCommit and TasteMapSourceFingerprint. Startup prints a non-content TasteMapBuildIdentity line with build, commit, fingerprint, renderer and referralAvailable. Source fingerprint is distinct from executable/Web hashes.

## Referral implementation inventory

One existing signed ProductionEnvironment.json referralAvailable=false policy. Shared React settings hides the entry; direct Referral page returns only existing unavailable/back UI before mounting any dashboard or registration effects. Browser adapter rejects dashboard calls. Native Settings and direct view are closed; both bridge methods reject before decoding/network work; invitation hints cannot be prepared or submitted by Apple sign-in. Disabled invite links cannot fall through into the generic Native Restaurant import handler. Ordinary Native public-share Universal Links now use the existing PublicShareRoute handler as onOpenURL already did.

Backend/model/API/Offer mapping/reward ledger/entitlement code retained. Source Worker guards are not represented as a new live deployment. Production sandbox_offer_forbidden remains unchanged. No second flag system, Debug-only enable, user URL/storage override, code inventory in app or entitlement bypass.

## Verification before device installation

- Clean formal Web build/typecheck and stage: PASS,26 resources byte-identical.
- Focused Referral/commerce/operator/shared UI/product-contract tests:149/149 PASS.
- Full Web suite:1475/1475 PASS,170 files (16:29:48 local run).
- Native compilation, signature, built/staged byte parity, release purity and installed identity: pending final build checks; append actual results below, never infer from source.

## Logs and privacy

Private archive: .private/device-smoke-2026090802, mode0700. Device console/event files mode0600. scripts/capture-device-smoke.mjs launches exactly the installed main Bundle once and captures console; it does not install, restart in a loop or control another build. Raw console remains private; only allowlisted non-content TasteMapBuildIdentity/TasteMapDiagnostic events enter shareable JSONL summaries.

Events cover auth session acceptance/logout, Sync pass start/end, authoritative entitlement refresh verified/failure, photo retry/upload/failure/delete, incoming links and Share import checks. No userID, photo path, URL, tokens, JWS or codes are logged by the added events. Map renderer identity is logged; Hybrid bridge is inactive in this Native-selected run and must not be claimed active. Actual Map gesture/visual behavior requires user evidence. Console capture ending on cold termination is a real gap to record/reconnect, not silently fill with another build's events.

## One consolidated user run

After exact-build installation/launch is confirmed, keep the phone connected and use only disposable records for mutation/delete tests. Report failed step/time/screenshot in one response; no repeat StoreKit purchase/Restore.

1. Settings: no Invite Friends row. Verify a prior invite link cannot enter attribution; no invite-code form. Premium remains reachable; do not buy or restore.
2. Auth: Apple sign-in, inspect Taste Map userID locally, logout/same-account login, verify historical data.
3. Map: sustained pan/pinch, marker select, Detail→Back viewport, Map→List→Map; report stalls/incorrect route.
4. Location: Allow, deny in iOS Settings, Settings→Allow, return and verify recovery.
5. Visit: create disposable Visit, edit/rate/add dish, save/reopen, delete and check absence.
6. Photo: Camera, PhotosPicker, upload; disconnect before a test upload, confirm failed/queued, reconnect/retry, delete test photo.
7. Sync: manual sync, offline mutation, reconnect, logout/login; delete+sync+restart and verify Visit does not resurrect.
8. Share Extension: supported Restaurant link with app closed and already open; correct destination/return. Notify test timestamps so console restart boundaries can be correlated.
9. Ordinary tastemap.cn public share link: cold and warm launch from Notes/Messages, correct content/back. No Referral B attribution required.
10. Final Visual and Map Gesture Smoothness: report PASS/FAIL for the Native renderer actually tested, not Hybrid. Only broken layout, wrong route, dead controls, severe stalls or wrong core data semantics block; no redesign requested.

## Gates (pending actual installed/user evidence)

NORMAL STOREKIT: PASS. REFERRAL REAL E2E: DEFERRED TO TESTFLIGHT INTERNAL BETA.
REFERRAL FIRST-TESTFLIGHT VISIBILITY: not yet installed-verified.
REAL DEVICE CORE SMOKE / FINAL VISUAL / MAP GESTURE SMOOTHNESS: USER ACTION REQUIRED, no failure or pass fabricated.
FINAL CUTOVER GATE: CLOSED. HYBRID_PRIMARY: NOT YET. FINAL RC: NOT YET. TESTFLIGHT READINESS: NOT READY.

Even after this Native run, Native visual/Map evidence is not substituted for Hybrid renderer acceptance. Do not cut over or generate Final RC in this task. Build2026090802 is PRE-CUTOVER ONLY, as are2026090801 and all older archives.

## Design System Compliance

Core: existing Settings/back/unavailable primitives retained. Food/Dining: unchanged. Canonical templates: only approved Referral availability affected. No new UI renderer, token scale or feature-flag framework. Installed visual/default-SwiftUI regressions remain a human gate; source tests are not visual acceptance.
