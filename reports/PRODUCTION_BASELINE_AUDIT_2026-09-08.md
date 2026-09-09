# Production candidate audit — 2026-09-08

SUPERSEDED GATES: the user explicitly replaced literal-string purity and optional-admin blocking rules. See [current TestFlight gate classification and deployed patch](TESTFLIGHT_GATES_RECLASSIFIED_2026-09-08.md). Core readiness and behavior-based purity now PASS; Production2d382c6d preserves the28 assets. The failures below describe the earlier audit policy/version, not current gate decisions.

## Decision and live identity

Keep the current deployment. **Candidate audit FAIL; formal adoption NO; cutover CLOSED.** No rollback, deployment, migration, real Gift/Reward issuance, offer redemption, or TestFlight upload was performed by this audit. Historical `29c76424-037c-418d-b607-7a3d07ed6f1d` is a rollback reference, NOT a requested restore target. Health, existing assets and Monthly/Annual remain in place.

At 04:48 UTC Cloudflare reports **`f8dd5e0f-c1cf-443e-bea5-14c5e119ab33` at 100%**, created 04:13:33 UTC, as the actual live version. It is a secrets-only successor of candidate **`ede1474e-cbaa-4e98-b75c-413af8ccc427`**: version-specific modules match exactly, assets routing matches, all existing bindings match, and only APP_STORE_ISSUER_ID / APP_STORE_KEY_ID / APP_STORE_PRIVATE_KEY secret bindings were added. Values were not printed or included here. This is not an unexplained frontend redeployment.

## Reproducible provenance

- Candidate source: **`a39cdaaaefa333e602d219a001ac5d61057da2eb`**, parent preserved checkpoint `bca94965d22b8c3ca43d29a179bb959e3e6c3191`.
- Original integration worktree: `/Users/lafayette/Projects/private-food-map-hybrid-final-integration`; deployment assets `.private/rc-worker-assets`, not current dist.
- Wrangler log: `/Users/lafayette/Library/Preferences/.wrangler/logs/wrangler-2026-09-08_01-53-44_002.log`; code deployment at 2026-09-08 01:54:10 UTC. Fifteen assets uploaded, thirteen reused, twenty-eight effective public files. Trigger changes were partial: API custom domain failed with error 100117; schedule/apex path routes succeeded.
- Independent detached reconstruction: `/tmp/tastemap-production-recovery.PXmKfO/candidate-source`, frozen lockfile install followed by the historical Web build and Wrangler dry-run. Rebuilt Worker is byte-identical to the version-specific downloaded module. Rebuilt dist is byte-identical to the deployed staging directory.
- Worker SHA-256, both candidate and live successor: `06bba9b051f3c382782767418ac3f99f2fa2c6157ada5a1b1b4759146575f2d1`.
- Old Worker SHA-256: `aff99612f1fe554128d22360de4903e9201c56f6a910038a4f618146ed0587b8`. Its original Web bytes remain incompletely recovered; no claim of exact old/new visual parity is made.
- Historical source/artifact searches and bundle/worktree inventory remain in `docs/PRODUCTION_ASSETS_RECOVERY_2026-09-08.md`. Protected foundation Git bundles and the prior deployment/migration report corroborate this chain.

## Three-way classification

A = old `29c76424`; B = candidate `ede1474e`; C = integration HEAD `73fc6d65c9a009554551dc59bc6a56ef6760bc92` plus explicitly uncommitted work. These labels classify rollout differences, not automatic authorization to deploy C.

| Area | A → B | B → C | Classification / release significance |
|---|---|---|---|
| Worker API | Health/readiness, verified-session gates, private-directory/preferences, Gift/Referral/trial APIs | HEAD Worker identical; local Admin error correction; concurrent Sandbox commerce edits | EXPECTED health; SAFE BUT EARLY additional business APIs; C dirty changes not certified as B |
| Web UI | New production bundle, including lazy Hybrid and Premium/Referral components; not an old-assets-only patch | Discovery threshold and Detail action corrections, associated tests | UNEXPECTED relative to original health-only scope; now retained as candidate, not automatically accepted |
| StoreKit config | Adds formal Monthly/Annual IDs and Production environment | HEAD same; live successor adds three secret bindings | EXPECTED; Production Apple API validation still unresolved |
| Auth | Production requires a verified Taste Map session, denies forged Access/test headers | HEAD same | EXPECTED hardening; successful signed-in end-to-end session not tested live |
| Premium | Authoritative server union includes Gift, reward and signup trial sources | Concurrent native reconciliation changes excluded from this audit | SAFE BUT EARLY; no new price/product or client unlock approved |
| Gift | Admin-controlled annual/lifetime grants/revoke/extend APIs | HEAD same | SAFE BUT EARLY; auth-negative probes pass; no real grants tested |
| Referral | Qualification, reward balance, settlement and audit; scheduled settlement every five minutes | Concurrent Sandbox assignment migration/backend work uncommitted | SAFE BUT EARLY; scheduler is active server behavior, not merely hidden UI |
| Admin | ID-only server HTML/API protection | Local malformed-token JSON correction | UNEXPECTED defect: live malformed token yields 500 HTML; missing configured admin; blocker |
| Sync | Existing /api and /api/v1 structure; production verified-session enforcement | HEAD same | EXPECTED; unauthenticated/forged identity denied; real account-switch sync pending |
| DB | Same DB binding; prior deployment applied 24 pending migrations through 0037, 38 ledger entries | New uncommitted 0038 Sandbox assignment schema appeared during audit | UNEXPECTED schema expansion relative to health-only request; previous replay/integrity evidence exists; do not replay or roll back blindly |
| R2 | Same taste-map-photos binding | Same production binding | EXPECTED unchanged binding; readiness HEAD passes, upload lifecycle not certified |
| Domain/routing | Health/ready/API/admin/invite/AASA Worker-first; api.tastemap.cn registration failed; apex remains separate Worker except explicit paths | Formal config still requests api.tastemap.cn | DANGEROUS release mismatch: shipping API authority is unreachable; blocker |
| Static assets | 28 public files, new hashes; old assets not preserved | Current Web build differs from B | UNEXPECTED initial rollout expansion; exact B/live parity now PASS; never substitute C dist |
| Release config | Central Production authority introduced, formal native primary retained | NATIVE_PRIMARY retained; concurrent Sandbox scheme is not final RC | EXPECTED centralization; device/cutover/archive gates remain CLOSED |

## Purity: strict requirement FAIL, no demonstrated active bypass

Scanned the candidate Worker plus public JS/CSS/HTML/JSON/manifest, and compared all 29 Worker/asset files against all 60 local inventory codes in memory: **zero code matches**, zero complete PEM private keys. No literal JWT token, absolute local path, `.private/` path, or the scanned fake-Premium/developer-switch patterns was found. This is evidence for these scans, not a mathematical claim that all possible secrets are absent.

The strict requested absence of development markers does NOT pass: Worker contains eight localhost/loopback matches, one api-dev hostname and eight development/test-identity matches. The public main JS contains a localhost check in the Dexie dependency. These are library detection, SSRF deny rules and guarded development helpers, not a configured Production API URL. Do not remove SSRF deny rules to manufacture a zero-string scan. Worker also retains Sandbox-capable Apple verifier branches and the PEM delimiter parser; these are not Sandbox secret values or a leaked private key. Runtime APP_ENVIRONMENT and APP_STORE_API_ENVIRONMENT are both production.

Forged debug/Access identity cannot authenticate the tested Production endpoints. Local Production boundary tests pass. Nevertheless, strict artifact purity is **not waived**, and verified real-device entitlement behavior is not claimed.

Formal products remain `com.lafayette.tastemap.premium.monthly.v1` and `com.lafayette.tastemap.premium.annual.v1`, matching the existing catalog setup evidence. No App Store Connect product was created or modified. Native prices continue to come from StoreKit Product/displayPrice. Transactions are re-fetched/validated server-side for bundle/product/environment and account ownership; React is not authorized to create entitlement.

Gift/Referral components are downloadable in the public lazy Hybrid chunk. The standard production browser entry selects legacy App; development query overrides are compiled out, and normal Hybrid selection requires the native bridge (or a separately compiled Hybrid build). Code inclusion is not an access-control boundary: a person can inspect or invoke downloaded code. Entitlement/admin endpoints remain server-authoritative; no real reward was issued to test reachability. Trial/referral settlement can be invoked by eligible authenticated users or the existing scheduler, so these are classified as early live business functionality, not harmless dormant text. Signed-in browser/phone acceptance remains UNKNOWN.

## Live regression and tests

At 04:50 UTC:

- `curl -i https://origin-api.tastemap.cn/health`: HTTP/2 200, content-type application/json, cache-control no-store, exact `{"status":"ok"}`.
- `/` and all **28/28 public static files**: HTTP200, byte and SHA-256 parity against the deployed staging package. Includes index, all directly referenced hashed JS/CSS, both Hybrid chunks, other lazy chunk, manifest, icons, images and catalog. A fresh second complete pass succeeded.
- D1 binding ID remains `064f6607-5464-4530-bc58-5f7d1e02f09f`; R2 remains `taste-map-photos`. Readiness reports database=true/photos=true. No user-data mutation performed.
- `/api/v1/sync/pull`, `/api/sync`, membership/entitlement, referrals, trial, StoreKit config, Admin HTML and Admin APIs: unauthenticated 401 JSON. Forged identity headers remain 401; foreign browser origin receives 403.
- `/internal/premium` with malformed Bearer: **500 HTML on Production**, rather than 401 JSON. No privilege granted. Local fix encloses this pre-API route in a safe JSON auth/error boundary; two regression cases added, focused six-file suite **50/50 PASS**. The local fix has NOT been deployed.
- `/ready`: **503**. storeKitConfigured=true means presence only; administratorConfigured=false. Production Apple notification-history verification evidence remains 401, while Sandbox was 200. Neither proves a completed purchase/renewal.
- Full current-workspace Web/Worker test snapshot: **1,433/1,433 PASS, zero failed/pending**, plus TypeScript PASS. Concurrent Sandbox tests appeared between runs (initial 1,425; after two local tests 1,427; final 1,433). A migration fixture assumed 0037 would always be last; changed to require inclusion while retaining exact applied/discovered list equality, schema checks and FK/quick checks. No test skipped or removed. Passing C tests do not retroactively test B binary behavior.
- api.tastemap.cn resolves to 120.26.235.179 and is unreachable from this host. Cloudflare DNS API403 prevents identifying/modifying the exact conflicting managed record. api-dev health was initially 500 but became **200 JSON** during external concurrent work; this audit did not deploy that change.
- Two paired available iPhones are visible to devicectl. No installation or purchase performed. Connection metadata is not a device smoke PASS.

API structure is **/api/**, including **/api/v1/**. Do not append an extra /api to the Base URL. Checked-in shipping Production Base URL is **https://api.tastemap.cn** (BLOCKED); **https://origin-api.tastemap.cn** is the currently working direct Worker origin, not an silently substituted shipping fallback. `/restaurants` and `/visits` are not top-level API paths.

## Required user-only actions, consolidated

1. **Cloudflare:** inspect/export the exact api.tastemap.cn DNS record, determine whether its Aliyun endpoint is still required, then resolve the conflict and attach the formal Custom Domain to private-food-map; alternatively provide scoped DNS access. Do not touch apex/api-dev/origin-api or delete an active relay blindly.
2. **App Store Connect:** resolve Production API 401 for the already-installed IAP credentials (active key, correct issuer/app scope/access). Do not resend secret values in chat or switch Production to Sandbox. Three secret bindings already exist.
3. **Admin identity:** nominate the authenticated Taste Map userID for MEMBERSHIP_ADMIN_USER_IDS. No arbitrary existing user is promoted. Configure via protected Worker settings; test authorization without granting a real Gift.
4. **Sandbox mapping:** provide the six batch-number → offer role → exact Apple Offer Identifier associations from App Store Connect. Existing batches 580777/580833/580852/580853/580908/580922 contain 60 unused codes, zero mapped batches. File ordering is not evidence; no actual code should be pasted. Inventory remains local `.private/sandbox-offer-codes/inventory.sqlite`, excluded from Git.
5. **iPhone/Apple account:** identify the intended paired iPhone and complete any required trust/unlock/Sandbox Apple sign-in prompts. Then execute isolated Sandbox Monthly/Annual purchase, restore, expiry and Offer tests, plus signed-in core smoke/account switch and AASA/Referral Universal Link checks. Do not use a real Production reward for these tests.

Once these are resolved, retest live readiness/auth/product configuration, review the local Admin patch and remaining artifact-purity policy before controlled release. No current pre-cutover archive qualifies as Final RC. Native primary, SwiftUI rollback and the TestFlight prohibition remain intact.

## Evidence and audit-owned files

Operator evidence root: `/tmp/tastemap-production-recovery.PXmKfO` (local, outside Git): `production-audit.json`, `successor-audit.json`, `current-assets-parity.json`, `current-public-assets`, `candidate-source`, `candidate-worker`, `web-tests-final.json`, `typecheck-final.log`, `boundary-tests.log`. Downloaded Worker modules and Cloudflare metadata stay local; no secrets/codes copied to tracked documentation.

Audit-owned code changes: `worker/index.ts`, `worker/productionBoundary.test.ts`, `worker/migrationFixture.test.js`. Documentation: this report, candidate metadata, health/recovery supersession notices, RC progress addendum. Concurrent native/commerce/Sandbox edits belong to other work and were not deployed or overwritten here.
