# StoreKit semantic integration and deployment readiness — 2026-09-08

## Provenance / preservation

- Target branch: `feature/hybrid-final-integration`; starting HEAD `73fc6d65c9a009554551dc59bc6a56ef6760bc92`.
- Source: `213db5c69b79945f22c0e6d51e747575d0cfc811`, `fix/storekit-environment-aware-rc`; source worktree clean and unchanged.
- Preserved 39 pre-existing modified/untracked files before editing in `/Users/lafayette/Projects/tastemap-storekit-integration-backup-nljGRyKv`.
- Semantic integration, not whole-file ours/theirs, branch merge, reset, rebase or forced checkout. Resulting HEAD is the integration commit containing this report; its exact hash is returned in the final handoff.
- Historical RC/health/recovery reports remain as evidence, not overwritten with a new deployment claim. Unrelated documentation changes remain uncommitted and preserved. Relevant concurrent backend, native service/test configurations and tests are included in the integration commit.
- During this task another window also modified `PremiumViews.swift` (13:33 local time), adding a compile-gated Sandbox catalog entry. That UI change is preserved but explicitly excluded from this integration commit. Build/tests describe the audited working tree including that external change, not a clean-checkout or Final RC claim; the normal Release scanner confirms its Sandbox UI marker is absent. No UI code was edited by this task.

## Conflict decisions

| Area | Integration decision |
| --- | --- |
| Apple verification | Source's authenticated JWS verification on both submitted and Apple-returned transactions; only 4040010 permits ID-only Production→Sandbox fallback. Preserve newer official Production host `api.storekit.apple.com`. |
| Apple ID variable | Use integration's `APP_STORE_APP_APPLE_ID` consistently; supersedes source branch spelling `APP_STORE_APPLE_ID`. Numeric, non-secret App Store Connect app ID; not yet configured. Missing ID fails readiness closed. Existing three credentials unchanged. |
| Trust anchor / runtime | One Apple Root CA G3 verifier with online checks; request-scoped library import. Compatibility exports delegate to the same verifier, not a second signature path. |
| Deployment flag | No build/deployment flag selects transaction authority. Signed payload decides the environment; Xcode/LocalTesting cannot become Apple Sandbox. |
| Ledger | Source environment-qualified v2 owners, transactions, immutable audit, notification UUID keys and isolated Sandbox entitlement projection replace legacy mixed projection. Identical IDs in two authentic environments coexist without overwriting either. |
| Offer binding / races | Preserve current operator assignment, qualified reward, user/token ownership and atomic original-subscription reservation. All six Offer-role race/duplicate tests retained. Operator receipt sync reads v2 Sandbox ledger, never a legacy or Production receipt. |
| Sandbox Offer policy | Existing isolated-development Offer test policy retained; normal Production-backed Sandbox subscriptions work independently. Dedicated Sandbox harness is not the formal Production build or Final RC. No real code allocated or redeemed. |
| Session isolation | Keep newer Native sessionGeneration checks across A→B→A, catalog await, purchase, restore, finish and refresh notification. Required JWS-capable protocol removes silent proof-dropping default implementation. Server session environment is authenticated and only changes after reconciliation. |
| Gifts / referrals | Existing independent rows and product rules retained; Sandbox projection cannot settle or overwrite Production rewards or membership tier. |
| Admin / readiness | Preserve malformed Bearer JSON rejection and actual JWT-signing infrastructure check. Gift Admin stays optional/non-blocking. Readiness now also requires both new migrations. |
| Dependencies / config | Retain newer lockfile, Node typing/compatibility, isolated native stores/schemes and Worker bindings; no dependency upgrades performed in this integration. |
| UI / products | No UI changes, Monthly/Annual IDs unchanged, NATIVE_PRIMARY retained. |

## Regression discovered by required F1-C4 gate

The first 44-test Native run failed only two F1-C4 tests (12 cascading issues). Actual blocker: `schema_unknown_field:websiteUrl`. Existing Swift encoder and shared JSON schema already supported this optional field, but Native preflight did not. After that was corrected, the older full-v1 fixture exposed a second compatibility defect: integrity verification re-encoded the DTO and inserted websiteUrl:null absent from the original payload.

Fix: allow the existing optional website metadata with HTTP/HTTPS, no credentials and bounded length; preserve HTTPS-only policy for image URLs. Compute canonical integrity from the supplied payload excluding integrity, not a DTO which can add optional fields. Type/shape/reference validation remains independently fail-closed. Tests cover old full/minimal fixtures, explicit null, HTTP, HTTPS, forbidden schemes/credentials, tampering and F1-C4 complete import. No existing assertion removed or skipped.

## Verification

- Web full suite: **1469/1469 PASS**, 168 files, zero skips.
- TypeScript typecheck and formal Hybrid build/stage: **PASS**, 26 staged files match dist bytes.
- Worker/StoreKit/auth/migration/real-crypto-negative/inventory targeted run: **82/82 PASS**, 9 files.
- Explicit Gift/Referral/Offer/StoreKit/Admin regression: **68/68 PASS**, 4 files.
- Swift: **61/61 PASS**, 6 suites: commerce, Premium, Referral, multi-account isolation, F1-C4 flow and backup preflight. Simulator only, not real Sandbox acceptance.
- Real local Workerd: health 200 JSON; malformed signed notification 400 JSON, no entitlement; actual request-scoped crypto startup works.
- Worker dry-run: **PASS**, 1589.22 KiB / gzip 302.07 KiB, using the preserved Production assets directory, not current Hybrid dist. No deploy.
- Final signed Release after final source changes: BUILD SUCCEEDED; codesign deep/strict PASS. Formal stage and built app each match all 26 dist resources byte-for-byte. Release purity PASS for 55 app files, including in-memory comparison with all 60 real inventory codes, no complete private key or .private directory, and signed ProductionEnvironment default exactly https://api.tastemap.cn. Reachable debug/test identity and Sandbox→Production contamination regressions PASS. No blanket localhost/isolated-Sandbox-string failure policy.

Audited working-tree artifact: `build/StoreKitIntegratedPreCutover/Build/Products/Release-iphoneos/TasteMap.app`. Executable SHA-256 `cfe5766b6542b4cf2dc0fc7636222521dd8a046ca02c8bd2759ae7f9f445b11a`. Not installed, archived or uploaded. Before selecting the real-device candidate, freeze all participating changes (including any separately approved UI work) and rebuild; do not relabel this mixed-working-tree artifact as a clean final commit build.

Detailed local evidence: `/tmp/tastemap-integration-web-full.log`, `tastemap-integration-typecheck.log`, `tastemap-integration-stage.log`, `tastemap-integration-focused-final.log`, `tastemap-integration-offer-regression.log`, `tastemap-integration-swift-final.log`, `tastemap-integration-release-verified.log`, `tastemap-integration-worker-dryrun.log`, `tastemap-integration-workerd.log` (all under `/tmp/`). Crypto business tests use explicit mock boundaries; real negative signature checks are separate. No real Apple positive transaction or notification is fabricated.

## Production preflight — no writes

Actual live version remains `2d382c6d-5a51-4339-8fa4-df918348030a` at 100%. This integration is **not deployed**.

| Surface | Read-only finding / planned delta |
| --- | --- |
| api.tastemap.cn | /health and unauthenticated /api/v1/sync/pull both connection failures; no Worker custom-domain binding. DNS gate blocks deployment. |
| Domains | origin-api → private-food-map and apex → fancy-fog-1341 remain. No main-site changes. |
| D1 | DB remains `064f6607-5464-4530-bc58-5f7d1e02f09f`, food-map-db. |
| R2 | PHOTO_STORAGE remains taste-map-photos. No upload/delete or binding change. |
| Secret names | APP_STORE_ISSUER_ID, APP_STORE_KEY_ID, APP_STORE_PRIVATE_KEY present; values not retrieved. |
| Vars | Existing Production/auth/bundle/monthly/annual/API-environment names retained; APP_STORE_APP_APPLE_ID absent. Admin ID absent and optional. |
| Migrations | Read-only remote list: 0038_sandbox_offer_assignments.sql and 0038_storekit_environment_isolation.sql pending. Neither applied. No replay of prior 38 migrations. |
| Assets | Preserved `.private/rc-worker-assets`: 28/28 byte/SHA-256 match live origin assets (one timed-out image succeeded on retry). Current Hybrid dist is not a deployment asset source. |

PRODUCTION DEPLOYMENT = BLOCKED BY DNS USER ACTION. No Worker upload/deploy, D1 migration, real Gift/Reward or code consumption in this task. No rollback necessary because no deployment attempted.

After DNS and configuration are ready, recheck live version/bindings/assets and concurrency. Use a frozen Worker-only candidate with the verified existing 28 assets, preserve secrets, apply reviewed migrations, then deploy under a controlled write window. Migration and Worker change must be coordinated: old code writes the legacy projection; do not run both writers during migration. A rollback plan must include the data-write boundary, not merely switching Worker versions. Post-deploy verify formal health, unauthenticated sync, DB/R2, auth, malformed Admin Bearer, forged/malformed notification rejection and existing core APIs before reporting Production PASS.

## User actions — once, in dependency order

### A. DNS / Custom Domain

- Website: Cloudflare dashboard.
- Menu: Websites → tastemap.cn → DNS → Records.
- Field: name api; current public A answer 120.26.235.179, TTL 300. Inspect actual row before deleting; current token lacks DNS inspection/write permissions.
- Value/action: remove only the confirmed stale api record; then Workers & Pages → private-food-map → Settings → Domains & Routes → Add → Custom Domain → api.tastemap.cn. Cloudflare creates/manages the proxied record. Leave apex, www, api-dev and origin-api alone.
- Return: “api Custom Domain 已保存”. Codex checks health 200 application/json status ok and unauthenticated sync 401 JSON. Do not substitute origin-api in the client.

### B. App's numeric Apple ID

- Website: App Store Connect.
- Menu: Apps → Taste Map → General → App Information → General Information → Apple ID.
- Field/value: that app's positive integer → `APP_STORE_APP_APPLE_ID`. Non-secret; not Apple Account, issuer, key ID or bundle ID.
- Return: numeric app ID for Codex to place in the reviewed Worker configuration. No new Apple key; no private key in chat.

### C. Notifications V2

- Website/menu: App Store Connect → Apps → Taste Map → General → App Information → App Store Server Notifications.
- Fields: Production Server URL and Sandbox Server URL, both Version 2.
- Value for both: `https://api.tastemap.cn/api/v1/storekit/notifications`.
- Timing: after integrated Worker/migrations and formal hostname are operational.
- Return: “两个 V2 URL 已保存”. Codex requests a real Sandbox test notification using existing credentials, verifies Apple delivery plus environment-qualified TEST audit. Previous actual request returned 4040007 URL-not-configured; not repeated against an unready endpoint.

### D. Sandbox Offer mapping

- Website/menu: App Store Connect → Apps → Taste Map → Monetization → Subscriptions → product/group → Offer Codes → each Offer → Sandbox batch.
- Field: batch suffix → Offer reference name and exact Apple Offer identifier.
- Value: fill the six rows; allowed names are 被邀请用户 14 天会员 and 邀请奖励 1–5. Never paste redemption codes.

| Batch suffix | Offer name / Apple identifier to return |
| --- | --- |
| 580777 | pending |
| 580908 | pending |
| 580853 | pending |
| 580922 | pending |
| 580852 | pending |
| 580833 | pending |

No mapping guessed, no allocation unlocked. Existing 60-code inventory remains private; this task does not redeem anything.

### E. Admin ID — optional, may follow TestFlight core work

- Device/menu: Production-connected Taste Map → Settings → Account & Security → Taste Map ID → Copy.
- Field: MEMBERSHIP_ADMIN_USER_IDS.
- Value: verified Taste Map user ID, explicitly nominated as admin, not email or Apple sub.
- Return: that ID and confirmation to authorize it. Codex configures it and verifies admin allowed, normal user/fake header denied. Gift Admin missing is NON-BLOCKING for ordinary app readiness.

### F. Real iPhone acceptance

- Device: selected physical iPhone, trusted/unlocked; install the exact merged Pre-Cutover candidate after backend prerequisites. No local StoreKit simulation configuration and no fake Premium.
- Menu: Taste Map Premium → Monthly/Annual product load → Monthly real Apple Sandbox purchase → authoritative Premium → Restore → logout/login/A→B→A. Dedicated isolated Offer harness tests invitee14d and Reward1 after mapping; do not label its development endpoint as formal Production-path proof.
- Core path: Apple login; Map pan/pinch/marker/viewport restore; location allow/deny→Settings→allow; Camera/PhotosPicker; Visit create/edit/rating/delete; photo upload/retry/delete; sync/offline→online; no resurrection; Share Extension and referral Universal Link cold/warm.
- Return: completion/failure and step/timestamp. Codex captures sanitized StoreKitVerification/AuthSession/Sync diagnostics, correlates server audit and fixes failures. Do not send codes/tokens/JWS. Physical interaction is required; Simulator gates are not substitutes.

## Cutover

FINAL CUTOVER GATE = CLOSED. HYBRID_PRIMARY = NOT YET. FINAL RC = NOT YET. No TestFlight upload or Archive. Architecture/code PASS and pending Production deployment are separate facts.
