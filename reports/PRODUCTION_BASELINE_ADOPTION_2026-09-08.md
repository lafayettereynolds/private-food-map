# Production adoption / Notifications gate closure

Latest first-TestFlight override: [Frozen StoreKit reconciliation](FROZEN_STOREKIT_RECONCILIATION_2026-09-08.md). Normal StoreKit real-device loop is PASS. Referral dual-account/Offer E2E moves to internal beta, conditional on verified first-build visibility DISABLED. The earlier two-path pre-TestFlight consumption requirement below is superseded. No second Apple Account is needed now. Real core smoke, visual and Map feel remain pending; baseline stays dd0369b9 ADOPTED.

## Baseline and provenance

CURRENT PRODUCTION BASELINE: **dd0369b9-26c1-4fe7-a23b-9a56f5887661 — ADOPTED / PASS**, explicitly confirmed by the user. `87b45679-2bc8-4f4b-b0a4-c82b65c155e9` is the previous verified baseline / rollback reference only, not the current baseline. No rollback or independent status-code patch.

The retained Cloudflare verification reports **dd0369b9-26c1-4fe7-a23b-9a56f5887661 at 100%**, deployment 004f01e3-47c7-42aa-a803-c9991c266c04, 2026-09-08T07:42:43.072015Z. Adoption is confirmed; no outstanding baseline-approval requirement remains. This documentation update does not claim a new live probe.

Both remote Worker modules have identical SHA-256 a3af88bf140f08d875c330efef1002b9852fa4a605f9a54d7748c322ae149f14. Source e03f0495e4655235251e31e225f4c6852aefd978; evidence HEAD 3ad22a00d9a675a5793ff74cc42756864f1152f3, in /Users/lafayette/Projects/private-food-map-storekit-production-deploy. Its reports/STOREKIT_PRODUCTION_DEPLOYMENT_2026-09-08.md describes the successor as an App Apple ID configuration correction. Code parity here does not assert all configuration values are identical.

Full 28-file hash set, source, deployment times, active bindings, routes, domains and variable/secret names only are recorded in production-baseline-candidate.json. No secret value was requested. No runtime edit, deployment, migration, DNS change, rollback or key creation occurred this turn.

## Verified Production regression evidence (retained)

| Check | Result |
| --- | --- |
| /health | 200 application/json, exact {"status":"ok"} |
| /ready | 200 JSON; worker/database/photos/authConfigured/storeKitConfigured true |
| Unauthenticated /api/v1/sync/pull | 401 JSON |
| Admin malformed Bearer | 401 JSON, invalid_access_token; no HTML/500 |
| Malformed Apple JWS | 400 JSON, invalid_apple_jws |
| Assets | 28/28 byte/SHA-256 matches, including index, JS/CSS/lazy chunks, manifest/icons/images |
| API.TASTEMAP.CN | PASS; Custom Domain private-food-map; HTTPS succeeds |
| D1/R2 | PASS; active bindings retained, database/photos readiness true |

An initial asset fetch had ECONNRESET; bounded retries completed all 28 comparisons. CORE PRODUCTION READINESS: PASS. PRODUCTION REGRESSION: PASS.

## Notifications — formally closed

APP STORE SERVER NOTIFICATIONS: PASS. SANDBOX TEST NOTIFICATION: PASS. SIGNED PAYLOAD VERIFICATION: PASS. UUID IDEMPOTENCY: PASS.

Accepted real evidence for 87 remains in APPLE_NOTIFICATIONS_MINIMAL_FIX_2026-09-08.md: Apple SUCCESS, TEST/V2.0/Sandbox verification, one audit row, duplicate replay and unchanged Premium/Reward state. The independent deployment report also records actual final-version SUCCESS and duplicate replay on dd0369b9, UUID SHA-256 4bf6c0e3bf6088ec5c2c2337a074955162e551fa9eac9890a9e14ec3fa2eeec2. This turn adopts existing actual evidence, not a newly generated Apple test.

Contract: malformed request/JWS may return 400 JSON; structurally valid but untrusted signature/certificate must return 401 or 403 JSON; valid V2 must return 2xx with verification, trusted environment, processing, audit and idempotency. Current malformed 400 is PASS and not a blocker. Earlier universal-401/minimal-patch deployment requirements are superseded.

## Offer mapping — VERIFIED / PASS

ASC page/filename evidence was already completed in the independent deployment report. This turn re-read inventory metadata only, not CSV contents or redemption-code values. No remapping mutation was needed.

| Sandbox batch suffix | Reference name / transaction offer identifier | Reward |
| --- | --- | --- |
| 580777 | 被邀请用户 14 天会员 | invitee 14 days |
| 580852 | 邀请奖励 1 | referrer slot 1, 30 days |
| 580833 | 邀请奖励 2 | referrer slot 2, 30 days |
| 580908 | 邀请奖励 3 | referrer slot 3, 30 days |
| 580853 | 邀请奖励 4 | referrer slot 4, 30 days |
| 580922 | 邀请奖励 5 | referrer slot 5, 30 days |

Inventory: /Users/lafayette/Projects/private-food-map-hybrid-final-integration/.private/sandbox-offer-codes/inventory.sqlite. All 60 unused; assigned/redeemed/failed all 0. No real code consumed, including Rewards 2–5. Existing ASC evidence says expiry September 13; no replacement batches generated.

Fresh scripts/sandbox-offers.test.js and worker/appStoreCommerceV1.integration.test.ts: **50/50 PASS**. Synthetic tests cover qualified-owner allocation, duplicate rejection, failed-code non-recycling, audit rollback, verified redemption ledger and Sandbox/environment guards. These do not replace real redemption evidence.

Git guard PASS: 2034 tracked/unignored files, 0 staged. Private in-memory matching produces counts only; no code displayed or added to reports. Inventory remains ignored; no Production inventory created.

## Approved two-path real-device plan

Deployed worker/appStoreCommerceV1.ts rejects Sandbox offerType=3 outside development with 403 sandbox_offer_forbidden. Formal Release is pinned to https://api.tastemap.cn; the isolated Sandbox scheme uses api-dev.tastemap.cn. Therefore the unchanged formal build cannot pass the two requested Sandbox Offer cases. Do not consume a code in that build or weaken the boundary silently.

Existing prepared artifact: /Users/lafayette/Projects/private-food-map-storekit-production-deploy/build/UniquePreCutover/Build/Products/Release-iphoneos/TasteMap.app. Version 1.0/build 2026090801, source e03f0495, evidence HEAD 3ad22a00, observed backend dd0369b9, 40 migrations per deployment evidence. Monthly com.lafayette.tastemap.premium.monthly.v1; annual com.lafayette.tastemap.premium.annual.v1. Signed Release/26-resource parity are prior evidence, not re-run here. No new build installed or frozen as full-matrix ready.

The user has approved the split. Production rejecting Sandbox Offers is an expected security boundary, not a bug or unresolved approval. PRODUCTION SANDBOX-OFFER ISOLATION: PASS.

Path A uses only the existing formal Pre-Cutover candidate build 2026090801 and https://api.tastemap.cn, without origin-api fallback. Test Monthly/Annual loading, normal Apple Sandbox Monthly purchase, verified transaction, server verification, authoritative Premium refresh, restore and A→B→A; Apple sign-in, MapKit pan/pinch/marker/viewport, location, camera, PhotosPicker, Visit create/edit/delete, photo upload/retry/delete, sync, offline/reconnect and deletion not resurrecting, Share Extension and Universal Link cold/warm.

Path B is an explicitly separate Sandbox build using private-food-map-development, https://api-dev.tastemap.cn, verified mapping and private Sandbox inventory. It is limited to invitee14 and Reward1: Offer redemption → Apple-verified Sandbox transaction → Sandbox server verification → Taste Map account binding → authoritative entitlement → Premium UI refresh. No Production entitlement/reward-ledger writes, inventory import, codes in the formal client, default endpoint switch or Debug verification bypass. Separate build authorization is not evidence that it has been built, installed or passed on an iPhone.

Rewards 2–5 remain covered by automated mapping/allocation/idempotency/isolation tests; real consumption is not required. All 60 codes remain controlled inventory; this update does not allocate or consume any.

NORMAL STOREKIT REAL DEVICE: USER ACTION REQUIRED.
INVITEE 14D REAL SANDBOX: USER ACTION REQUIRED.
REWARD 1 REAL SANDBOX: USER ACTION REQUIRED.
REAL DEVICE CORE SMOKE: USER ACTION REQUIRED.
FINAL VISUAL / MAP FEEL: USER ACTION REQUIRED.
FINAL CUTOVER GATE: CLOSED.
HYBRID_PRIMARY: NOT YET.
FINAL RC: NOT YET.
TESTFLIGHT READINESS: NOT READY pending actual iPhone evidence and final visual/Map feel confirmation.

Baseline, Notifications and Offer mapping are closed. The five remaining gates are normal StoreKit, invitee14, Reward1, critical smoke and final visual/Map feel. Only after all pass may NATIVE_PRIMARY become HYBRID_PRIMARY, preserving SwiftUI rollback code.

After cutover, generate a new clean Web build, stage assets, HYBRID_PRIMARY Release, signed device build and Archive, then final purity, asset byte parity, full regression, F1-C4, account isolation and Premium/Gift/Referral regression. Build 2026090801 and every existing Pre-Cutover Archive are ineligible to be renamed Final RC. Only the new accepted Archive can become FINAL RC PASS, then proceed to TestFlight.
