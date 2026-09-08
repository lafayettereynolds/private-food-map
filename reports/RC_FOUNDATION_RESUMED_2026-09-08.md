# Production foundation resumed — 2026-09-08

This supersedes the earlier read-only audit for the facts below. It is **not RC approval**. Lafayette released the shared window, then deferred Apple credentials and Sandbox Offer mapping; no further questions were sent. No UI redesign, real Gift issuance, Sandbox redemption, real-device installation, or Hybrid primary cutover was performed.

## PHASE: preservation and regression baseline

STATUS: COMPLETE

WHAT CHANGED: Protected tracked/index patches and untracked archive in `/Users/lafayette/Projects/tastemap-rc-resume-yKGy6yVt`. Reconstructed the exact pre-change product in a detached verification worktree, committed it as `bca94965d22b8c3ca43d29a179bb959e3e6c3191`, and fast-forwarded integration to that checkpoint without replacing working files. The temporary verification dependency symlink is removed from the following foundation commit; no dependency directory is deleted. Earlier history is preserved.

TESTS: Baseline Vitest: 1,414 tests, 1,390 pass, 24 fail. Current: 1,421 tests, 1,398 pass, 23 fail. The migration fixture's obsolete last-file assertion was updated to 0037, with actual table/integrity assertions added. All other failing tests already fail in the protected baseline. A Swift package owner-isolation fixture also fails and crashes with out-of-range indexing in both trees. Baseline failure is not a release waiver.

PRODUCTION EVIDENCE: Not applicable.

USER ACTION REQUIRED: None now.

BLOCKERS: Remaining regression failures need closure before final RC; they are not covered by the foundation-only tests.

COMMIT: Baseline bca94965d22b8c3ca43d29a179bb959e3e6c3191; foundation delta is the commit containing this report.

## PHASE: production environment, authorization and deployment

STATUS: BLOCKED

WHAT CHANGED: `ProductionEnvironment.json` is the checked-in non-secret authority for Native Release, Browser production and Worker public origin/App ID. Native Release ignores process overrides; Browser production ignores local environment URL overrides. Share Extension queues through App Group and has no independent HTTP endpoint. Added exact-origin Browser CORS, verified-session enforcement for Production legacy API, ID-only admin access, protected admin HTML and truthful `/ready`. Formal invite URLs use tastemap.cn. No new proxy layer.

TESTS: Typecheck and focused boundary/readiness/health tests pass. Formal Web build/stage passes. Forged Cloudflare identity/test-user headers do not authenticate Production.

PRODUCTION EVIDENCE: Worker `private-food-map`, active version `ede1474e-cbaa-4e98-b75c-413af8ccc427`, deployed 2026-09-08T01:54Z. `https://origin-api.tastemap.cn/health` returns JSON 200. `/ready` returns 503 with database=true, photos=true, storeKitConfigured=false, administratorConfigured=false. `/internal/premium` and unauthenticated legacy/v1 sync return 401 even with forged identity headers. Main site, privacy and support still return 200.

Deployment exit was nonzero because trigger update was **partial**: code, schedule and main-domain path routes succeeded; `api.tastemap.cn` custom domain failed with Cloudflare 100117 (externally managed DNS record already exists). Existing origin-api domain remains bound. DNS API permission returns 403, so this tool session cannot inspect/delete the conflicting record. Public DNS currently resolves api to 120.26.235.179. Main `tastemap.cn` remains on `fancy-fog-1341` except the two explicit routes. No Aliyun relay requirement was established.

USER ACTION REQUIRED: Deferred, not an immediate question. Cloudflare → tastemap.cn → DNS → Records: review/export the exact `api` record currently pointing to 120.26.235.179, then remove the conflicting record if it is the retired API endpoint. Workers & Pages → private-food-map → Settings → Domains & Routes → Add Custom Domain → api.tastemap.cn. Do not change apex, api-dev or origin-api records. Afterwards verify health JSON 200 and HTTPS; ready remains 503 until missing configuration is supplied. Alternatively grant this session scoped DNS access for Codex to complete that exact change.

BLOCKERS: Official API domain unavailable; App Store credentials and admin ID absent. Origin health does not mean formal Production foundation PASS. The CORS response tests are local until api-domain routing exists.

COMMIT: Foundation delta containing this report.

## PHASE: migrations, Gift/Referral and private photos

STATUS: BLOCKED

WHAT CHANGED: Verified DB ID `064f6607-5464-4530-bc58-5f7d1e02f09f` and private R2 binding `taste-map-photos`. Exported real DB to protected `production-before.sql` outside Git; rehearsed all pending migrations against that copy and verified ID preservation before applying. Applied 24 pending files, 0015 through 0037, including both distinct 0036 filenames. D1 split unparenthesized trigger SELECT CASE expressions incorrectly; semantically equivalent SELECT (CASE ... END) fixed 0034/0035/0036 preferences/0037. Failed migrations rolled back before retry. No filenames renamed; Wrangler ledger prevents replay.

TESTS: Gift/referral/signup 31 targeted tests passed, preferences/signup 25 passed. Remote ledger now contains 38 migrations; foreign_key_check empty, quick_check=ok. Preserved users=1, restaurants=24, visits=23, photos=0; rehearsal preserved their identifier sets. Time Travel bookmark call failed with Cloudflare internal 7500; protected SQL export exists and was successfully replayed.

PRODUCTION EVIDENCE: D1 queries above ran on the verified Production ID. `/ready` successfully queries the migration ledger and performs a private R2 HEAD. No real Gifts issued or user content deleted. R2 HEAD is **not** upload→fetch→delete proof. No authenticated operator account was fabricated.

USER ACTION REQUIRED: Deferred. Configure Worker secrets APP_STORE_ISSUER_ID, APP_STORE_KEY_ID, APP_STORE_PRIVATE_KEY and MEMBERSHIP_ADMIN_USER_IDS through Cloudflare Settings → Variables and Secrets. Never paste private key/token into chat. Later perform controlled authenticated photo smoke with an authorized test account; Codex can diagnose metadata/R2 access and verify owner isolation.

BLOCKERS: Real R2 lifecycle, authenticated admin mutation and Apple transaction proof unexecuted. Credentials being present alone will not validate them. Recovery: prefer compatible Worker rollback/forward schema correction; full DB export restore requires reviewing all post-export writes, not blind rollback.

COMMIT: Foundation delta containing this report.

## PHASE: Universal Links and native build

STATUS: BLOCKED

WHAT CHANGED: Added applinks:tastemap.cn to Release entitlement, retained Apple sign-in and App Group. Routed main-domain AASA and /invite/* to Production Worker while preserving existing website. No Bundle ID or StoreKit product ID changed.

TESTS: AASA HTTP200 declares 7G5J9MJX88.com.lafayette.tastemap with /invite/* and existing /share/*. Invalid invite safely returns 404. Signed generic-device Release build succeeds; codesign verification succeeds. Built entitlement contains Associated Domains. Built ProductionEnvironment.json is present. All 26 Web files match formal stage byte-for-byte. Existing purity scanner passes 55 app files / 26 Web files.

PRODUCTION EVIDENCE: `https://tastemap.cn/.well-known/apple-app-site-association` is live. No valid referral code was minted merely for smoke, and no installed/cold/warm attribution PASS is claimed. Existing /share/* routing was not changed or certified by this phase.

USER ACTION REQUIRED: Later real iPhone Universal Link and registration/first-Visit attribution smoke. App Store Connect privacy answers still require retrieval/comparison with the actual declarations; the existing privacy policy was not rewritten.

BLOCKERS: Signed development-device build is not App Store distribution readiness (get-task-allow=true). Source/stage/build parity does not prove current iPhone behavior. Real device matrix remains in the initial audit report.

COMMIT: Foundation delta containing this report.

## PHASE: StoreKit, cutover and final RC

STATUS: DEFERRED

WHAT CHANGED: No cutover; Release remains NATIVE_PRIMARY because prerequisite gates have not closed. Current signed build is explicitly pre-cutover verification, not the final RC. Sandbox inventory guard passed without exposing or redeeming any of the 60 codes. Mapping remains deferred at Lafayette's request.

TESTS: No real Monthly/Annual purchase, restore, renewal, expiry or Offer redemption claimed. No real-device smoothness PASS. Full automated suite remains failing as recorded above.

PRODUCTION EVIDENCE: No TestFlight upload, gift issuance or Sandbox transaction.

USER ACTION REQUIRED: None requested now. Deferred items are retained for Lafayette's return; Codex must finish remaining automated/regression work before asking for final upload actions.

BLOCKERS: Official DNS, server credentials, authenticated lifecycle checks, regression closure, StoreKit Sandbox and real-device evidence. Final clean build/archive/purity must be repeated after an authorized gate-compliant cutover.

COMMIT: Foundation delta containing this report.

## Overall gates

- PRODUCTION FOUNDATION: FAIL — partial infrastructure deployment only.
- PREMIUM / REFERRAL: FAIL — code/schema deployed; live auth/Apple lifecycle proof incomplete.
- REAL DEVICE PREPARATION: FAIL — build/matrix available, executable Sandbox conditions incomplete.
- STOREKIT SANDBOX: FAIL — deferred/unexecuted.
- HYBRID_PRIMARY CUTOVER: FAIL — intentionally not performed before prerequisites.
- RELEASE RC: FAIL — pre-cutover build only, regression failures remain.
- RELEASE PURITY: FAIL for final RC (current pre-cutover artifact scanner passes; final artifact does not yet exist).
- TESTFLIGHT READINESS: NOT READY.

No secrets, redemption codes, raw Production export or signed download URL belong in this report or Git.
