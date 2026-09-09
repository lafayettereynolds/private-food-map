# TestFlight gates reclassified — 2026-09-08

## Latest authoritative update — baseline adoption

Latest user decision and evidence reconciliation: [Frozen StoreKit / first TestFlight preparation](FROZEN_STOREKIT_RECONCILIATION_2026-09-08.md). NORMAL STOREKIT REAL DEVICE is PASS (seven frozen actual iPhone/Apple Sandbox checks), not downgraded by unrelated gates. Referral E2E is deferred to internal beta and becomes non-blocking once first-build visibility is proven DISABLED. Source guards pass88 tests; signed/installed artifact closure is still pending amid concurrent edits. Core smoke, final visual and Map smoothness remain user-action gates. This supersedes the prior two-path requirement to consume Offers before first TestFlight.

See [Production baseline adoption](PRODUCTION_BASELINE_ADOPTION_2026-09-08.md) and production-baseline-candidate.json. This update supersedes conflicting current-state/blocker statements below, which are retained as historical evidence.

- CURRENT PRODUCTION BASELINE: dd0369b9-26c1-4fe7-a23b-9a56f5887661 — ADOPTED / PASS by explicit user confirmation. 87b45679 is the previous verified baseline / rollback reference only. No baseline confirmation remains pending.
- Core Production, regression, formal API domain, D1/R2, 28/28 asset parity: PASS.
- Notifications V2, real Sandbox TEST, signed verification and UUID idempotency: PASS, formally closed. Malformed JWS 400 JSON is valid and is NOT a blocker; no status-only patch.
- Sandbox Offer mapping: PASS; all 60 codes unused. Fresh operator/commerce tests 50/50 PASS; Git guard PASS.
- Two-path plan APPROVED: formal candidate 2026090801 uses api.tastemap.cn for normal StoreKit/core smoke; separate Sandbox build/Worker/inventory only for invitee14 and Reward1. Production sandbox_offer_forbidden is an expected PASS security boundary, unchanged. Remaining gates: normal StoreKit, invitee14, Reward1, critical smoke, final visual/Map feel — all require real-device/user evidence.
- Cutover CLOSED; NATIVE_PRIMARY retained; Final RC NOT YET; no TestFlight upload.

## Historical outcome before final baseline adoption

This report supersedes the literal-string purity and optional-admin classifications in the earlier Production baseline audit. **Core Production readiness PASS. Behavior-based Production purity PASS. StoreKit environment architecture PASS for the implemented signed-data/lookup paths and automated tests; real StoreKit acceptance remains pending.** Gift Admin is NON-BLOCKING. Production Apple transaction verification is deferred to the App Store production release gate, not treated as an independent TestFlight blocker.

Do not interpret these as Final RC approval. Formal API domain acceptance is now PASS (2026-09-08 13:50 CST). Actual Sandbox transactions/notifications, offer mapping and real-device core smoke remain open. NATIVE_PRIMARY is retained; no TestFlight upload, cutover or Final RC archive was performed. No real Gift/Referral reward or code was issued/redeemed in this task.

## Deployed patch and evidence

- Production: **`2d382c6d-5a51-4339-8fa4-df918348030a`**, 100%, private-food-map.
- Development/Sandbox API: **`7d7cd87f-11a2-4ba8-ae88-b57fddb01a7a`**, private-food-map-development.
- Production patch prepared independently in `/tmp/tastemap-production-recovery.PXmKfO/gate-patch`, detached from the exactly reproduced source `a39cdaaaefa333e602d219a001ac5d61057da2eb`. Only Worker/backend dependency/config changes were overlaid. Current workspace frontend changes were not published.
- Previous live `f8dd5e0f-c1cf-443e-bea5-14c5e119ab33` remains the immediate historical rollback reference; `29c76424` is not a requested restore target.
- Production upload reused every effective public asset: no new static files uploaded. Deployment preserved the existing origin custom domain, apex AASA/invite path routes and schedule. The unresolved api.tastemap.cn registration was omitted from the isolated deployment config; main checked-in config still declares the intended formal domain. The apex website Worker was not replaced.
- Production Worker SHA-256: **`7139144c4761ebd47d3ab6839473f4768283274ff1b08f288c8e99bce983bf34`**, exact match between independent dry-run output and version-specific remote metadata.
- Post-deployment **28/28 public assets byte/SHA-256 parity PASS**, including index/JS/CSS/lazy chunks/manifest/icons/images.
- D1/R2 bindings unchanged, no Production migration/data write by this task. Read-only schema check confirms users/restaurants/visits/auth_sessions/auth_challenges/app_store_accounts/app_store_transactions. Apple public Auth JWKS returned200.
- `/health`:200 JSON exact `{"status":"ok"}`. `/ready`:200 JSON. Unauthenticated sync401; malformed Admin Bearer401 JSON; forged Admin identity401; forged Apple signed notification401 JSON. These checks passed on Production, not only Node mocks.

## Behavior-based purity

| Criterion | Result and evidence |
|---|---|
| REACHABLE DEBUG BYPASS | NO observed/reachable through audited Production auth routes; production guards precede development identity fallback; forged identity probes denied |
| REAL SANDBOX CODES IN RELEASE | NO; all60 inventory values compared in memory against78 Worker/public/native artifact files, zero matches |
| SECRETS IN CLIENT BUNDLE | NO found; native Release scanner passes49 files/26 Web resources; complete private-key scan zero; no client administrative credential surface |
| PRODUCTION DEFAULT ENDPOINT | https://api.tastemap.cn, without /api suffix; formal domain acceptance PASS, no origin-api or development fallback |
| SANDBOX SUPPORT CORRECTLY ISOLATED | YES for verified transaction routing and recorded environments; Development rejects Production transactions; same transaction/subscription cannot overwrite another environment |
| Debug/fake Premium | Not exposed in the scanned normal Release artifact; membership still comes from authoritative service; Gift/Referral rows preserved by Apple reconcile/refund |
| `.private` contents in artifacts | No actual code or key matches; no private directory content intentionally staged; Git guard checked2025 tracked files and passed |
| Production accepted by Sandbox verifier | Rejected by verifier environment/bundle validation and authenticated API response matching; automated negative tests retained |

Dependency localhost detection, SSRF deny constants and correctly gated development/Sandbox implementations are NOT failures under the updated rule. The Apple root CA embedded in Worker is a **public certificate**, not a private key. Native Auth/Keychain implementations necessarily exist; credentials must not cross into React or static assets.

Evidence is scoped: security scans cannot prove absence of every imaginable secret, and automated account tests are not real-phone account-isolation acceptance. No literal-string waiver authorizes an actual bypass.

## Core readiness versus Gift Admin

Ordinary login/sync/restaurant/Visit/photo/Premium/referral/startup routes do not consult MEMBERSHIP_ADMIN_USER_IDS; only internal/admin operations do. Missing admin is therefore non-blocking.

`/ready` now returns core checks for running Worker, D1 migration readiness, private R2 HEAD, Auth configuration and StoreKit signing infrastructure. StoreKit check actually imports the configured key and signs a JWT; mere presence of three strings no longer passes. It does not claim that Apple accepted a purchase. Schema checks, Auth JWKS availability and unauthorized core API probes supplement the endpoint; signed-in core smoke remains a separate gate.

Optional status is exposed as booleans in the existing response, with no new public endpoint:

```json
{"status":"ready","checks":{"worker":true,"database":true,"photos":true,"authConfigured":true,"storeKitConfigured":true},"optional":{"giftAdmin":{"configured":false,"blocking":false}}}
```

Admin malformed-token handler was deployed and returns401 JSON, not500 HTML. Missing admin does not allow anyone through. Found only historical user `owner` / nickname Lafayette and zero active owner sessions; this is insufficient evidence to promote it as the current authenticated administrator. Optional action: Taste Map → 设置 → 账户与安全 → Taste Map ID → copy that ID. Do not send Apple account ID/email/token. Positive real admin access cannot be claimed until identity is selected and configured; negative boundaries already pass.

## Apple credentials and environment-aware StoreKit

Existing keys retained, not rotated/re-requested. Sandbox API HTTP200 is established prior credential evidence; Production401 is not explained away as proven pre-release behavior. Current Production readiness proves the existing configuration can import the key and generate a JWT. JWT uses ES256, kid/iss, appstoreconnect-v1 audience, bid and a bounded expiry. No discovered JWT construction defect is being waived.

**APPLE PRODUCTION TRANSACTION VERIFICATION: DEFER UNTIL APP STORE PRODUCTION TRANSACTION EXISTS.** Re-test actual Production transaction/API access before App Store public release. A generic401 is an authentication error, not TransactionIdNotFound and does not authorize Sandbox fallback.

Implemented routes:

1. Purchase/restore/Transaction.updates sends StoreKit verification result's JWS from Native directly to the authenticated server, independent of DEBUG/Release configuration.
2. Apple official SignedDataVerifier validates certificate chain anchored in Apple Root CA-G3, JWS signature, bundle and environment with online checks enabled. A decoded hint can select the verifier but is never accepted without cryptographic verification.
3. Trusted Sandbox selects Sandbox Server API; trusted Production selects Production API. API response transaction ID, bundle, product, environment, dates and appAccountToken are independently checked before projection.
4. Legacy ID-only lookup defaults to Production on Production Worker. Only404 with Apple errorCode4040010 retries Sandbox. Generic404,401,403,429 and500 do not.
5. Transaction environment is stored accurately. Cross-environment reuse of a transaction or original subscription is rejected. Duplicate transactions remain idempotent; account ownership cannot move A→B; Gift/Referral rows are not deleted or overwritten.

Production signed-data verification additionally requires non-secret numeric **APP_STORE_APP_APPLE_ID** (the app's App Store Connect Apple ID, not a person's Apple account). No value was found in available project metadata, and ASC browser is logged out. Sandbox does not require this value. This is a **Production signed-notification/transaction release follow-up**; do not invent the ID or generate a new key. Populate the checked-in non-secret configuration once confirmed so a later deployment cannot erase it.

The existing isolated Sandbox Offer ledger remains Development-only: actual codes stay local and the Production Worker does not import that inventory. Normal Production-backed TestFlight transactions are supported by the new environment-aware path; the dedicated Sandbox E2E/ReleaseSandbox build uses isolated development persistence for the supplied reward-code tests. That dedicated test archive is not the normal production build and is NOT Final RC. A successful isolated test must not be relabeled as proof of a Production-DNS end-to-end run.

## Notifications V2

Latest update: Notifications V2 delivery/audit/replay PASS is closed on the adopted dd0369b9 baseline. Malformed JWS 400 JSON complies with the revised contract. No independent minimal patch is required. Earlier 87b45679 acceptance and 2d382c6d failure evidence below are historical and must not override the current PASS. This is not Final RC approval.

### Latest live acceptance — 2026-09-08 14:20 CST

This update supersedes the logged-out/Issuer-ID-missing handoff below. ASC login is now available. Both Production and Sandbox callback URLs were previously unset; both were saved as `https://api.tastemap.cn/api/v1/storekit/notifications` and confirmed after navigating away and re-entering App Information. The current UI exposes no version selector. Actual Sandbox payload is verified as version2.0; Production payload/version delivery has not been exercised.

Confirmed app identity: Apple ID `6804560641`, bundle `com.lafayette.tastemap`. Existing IAP Key ID and Issuer ID were read from Users and Access → Integrations → In-App Purchase and matched to the existing local subscription key. No credential regeneration, rotation, upload or disclosure occurred. The numeric app ID is now known, but this turn did not change Worker configuration or deploy it.

Real Apple Sandbox TEST results:

| Check | Result |
|---|---|
| Initial request immediately after URL save | HTTP404 / Apple4040007 (notification URL not yet found) |
| Subsequent real TEST requests | Apple returned testNotificationToken; tokens retained only in memory, not logged |
| Apple delivery status | `UNSUCCESSFUL_HTTP_RESPONSE_CODE`; six status polls for the first accepted request, same failure for the second |
| Official local SignedDataVerifier, online checks enabled | PASS for the second real signedPayload, Apple root trust anchor, expected bundle and Sandbox environment |
| Verified fields | notificationType=TEST, version=2.0, environment=Sandbox, bundleId=com.lafayette.tastemap |
| Same genuine payload replay to formal Production callback | HTTP401 JSON, code=invalid_apple_signed_data |
| Production TEST audit rows since06:10 UTC | 0; read-only D1 query, zero writes |
| notificationUUID idempotency | NOT VERIFIED live: signature rejection prevents acceptance/audit insertion |
| Final core endpoint regression | health200 exact JSON; unauthenticated sync401 JSON |

For correlation only, SHA-256 of the second verified notification UUID: `baf055f84151aa81c2f3a4b4c9e48fbe42f5c60581458c8c54db71eef917fa31`. No full UUID, signedPayload, private key or test token is stored here.

**APP STORE SERVER NOTIFICATIONS: FAIL — live Worker verification rejects genuine Apple Sandbox JWS.** This is no longer a login or missing-URL blocker. Current live Worker is still `2d382c6d-5a51-4339-8fa4-df918348030a`; its verifier masks internal verification errors as401. Root cause within its verification/runtime path is not yet certified. Local integrated source and pending `appleNodeFetch` compatibility work are not deployed evidence. No new migration, Worker deployment, DNS/Custom Domain change, Hybrid cutover, Final RC or TestFlight upload was performed during this acceptance. Next step is a separately scoped minimal Worker verification fix/deployment, preserving production assets and bindings, followed by the same genuine delivery/audit/idempotency acceptance.

References: [Apple4040007](https://developer.apple.com/documentation/appstoreserverapi/servernotificationurlnotfounderror), [Server notification URL configuration](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/enter-server-urls-for-app-store-server-notifications).

### Earlier implementation evidence and setup handoff

Reused **POST /api/v1/storekit/notifications**. Existing function name ends V1 because the Taste Map API namespace is v1; this is not Apple's legacy notification format.

- Previously the outer signedPayload was merely decoded. It is now cryptographically verified before UUID/database/API processing.
- Verified data.environment selects the matching Apple API. Fresh server lookup, not untrusted notification type or dates, decides entitlement.
- notificationUUID idempotency retained; insert is conflict-safe. TEST and unknown no-transaction events are acknowledged/logged without granting anything.
- Automated cases cover renewal, expiry, revoke, refund, unknown events, TEST and duplicate handling. Forged payload denied in both local Worker runtime and live Production.
- Official library's jsrsasign dependency initially failed Worker global initialization due to random generation; request-scoped lazy import fixes it. Node compatibility flag enabled for both Worker configs. A successful dry-run alone was not used as runtime acceptance.
- **Genuine signed Apple notification delivery is not yet verified.** No real transaction or test notification was fabricated.

Intended App Store Connect final configuration after DNS is fixed:

```text
Production Server URL: https://api.tastemap.cn/api/v1/storekit/notifications
Sandbox Server URL:    https://api.tastemap.cn/api/v1/storekit/notifications
Version: V2
```

For the existing isolated Development-account E2E run, use `https://api-dev.tastemap.cn/api/v1/storekit/notifications` as the Sandbox callback while that run is active. Its D1 account tokens/rewards are separate; do not expect a Development transaction to attach to a Production account. Restore the shared formal URL for normal Production-backed TestFlight testing. Setup navigation: App Store Connect → Apps → Taste Map → App Information → App Store Server Notifications. Request a genuine Sandbox TEST notification after configuration, then verify its UUID/acknowledgment without a purchase. Production delivery remains a public-release follow-up.

## Formal domain acceptance — 2026-09-08 13:50 CST

**API.TASTEMAP.CN: PASS**

- Read-only Cloudflare Workers Domains API returned200 and confirmed `api.tastemap.cn` → service `private-food-map`, environment `production`, enabled=true. Existing origin-api, api-dev and apex domain entries remain present. No DNS, domain, route or Worker deployment mutation was performed.
- Authoritative `kim.ns.cloudflare.com`, public resolvers1.1.1.1/8.8.8.8 and finally the default local resolver returned104.21.67.13 /172.67.167.153, not120.26.235.179. The initial local stale answer is recorded below as historical evidence; it subsequently expired without changing local settings.
- Unmodified `curl -i https://api.tastemap.cn/health`: HTTP/2 200, content-type application/json, exact body `{"status":"ok"}`.
- Unmodified `curl -i https://api.tastemap.cn/api/v1/sync/pull`: HTTP/2 401, content-type application/json; charset=utf-8, body `{"error":"A verified Taste Map session is required."}`.
- Separate IPv4 repeats also passed: health200 at172.67.167.153; sync401 at104.21.67.13. Ordinary health also reached Cloudflare IPv6. Final acceptance did not rely on `--resolve`; that flag was used only for the initial stale-DNS diagnostic.
- TLS verification succeeded without `-k` (curl ssl_verify_result=0). SAN matches api.tastemap.cn; issuer Google Trust Services WE1; validity2026-09-08 04:45:22 UTC through2026-12-07 05:45:19 UTC.
- Normal Production client: `ios/TasteMap/TasteMap/Configuration/ProductionEnvironment.json` has exact `https://api.tastemap.cn`. AppEnvironment.swift normal non-DEBUG/non-Sandbox path reads this bundled resource only, ignores process overrides and has no origin-api/local/staging fallback. `/api/v1` belongs to request paths, not the base. The dedicated compile-time Sandbox build remains separate and is not the normal Production client. No new build/archive is claimed.

### Notifications V2 continuation

ASC's existing Chrome tab was inspected and is still at the Apple account login screen (`authResult=FAILED`). Neither URL configuration nor genuine signed delivery can be certified from that state. The existing subscription .p8 was located locally and was not printed, copied, modified or regenerated. The current process and inspected local credential/settings metadata do not provide the paired Issuer ID; deployed secret bindings cannot be read back as plaintext.

The existing `scripts/storekit-test-notification.mjs` uses Apple's official Sandbox client to request TEST and query delivery status without printing keys/JWTs/payloads/test tokens. No request was sent with guessed credentials, and no synthetic notification was labeled genuine. Next required user action: sign in to App Store Connect in the existing Chrome tab, then resume configuration of both formal callbacks below as V2 and retrieve the existing non-secret key metadata. Verify Apple's delivery status and the server's verified TEST audit row before closing this gate. No key rotation, Production purchase, Hybrid cutover, Final RC or TestFlight upload was performed.

## Historical DNS handoff — superseded, do not execute

The following reflects the earlier pre-binding state only. The user has now completed binding; the current instruction prohibits further DNS or Custom Domain changes.

```text
网站: https://dash.cloudflare.com/
菜单: tastemap.cn → DNS → Records
DNS provider: Cloudflare (kim.ns.cloudflare.com / yew.ns.cloudflare.com)
当前记录: api.tastemap.cn public A answer 120.26.235.179; no public AAAA/CNAME answer
是否删除: 先导出/核实精确 api 记录及其阿里云用途；仅在确认为不再需要或已批准替换时移除冲突记录
是否新建: 通过 Worker Custom Domain 创建受管理记录，不手工添加新的 IP
记录类型: Worker 管理的 Custom Domain DNS 记录；由 Cloudflare 创建
记录名称: api.tastemap.cn
记录目标: private-food-map Worker（不是手填 120.26.235.179，也不是另一个猜测 IP）
Proxy: 由 Worker Custom Domain 管理；现有记录的 Proxy 状态尚无法核实
Worker Custom Domain 菜单: Workers & Pages → private-food-map → Settings → Domains & Routes → Add → Custom Domain → api.tastemap.cn
验证命令:
curl --max-time 20 -i https://api.tastemap.cn/health
curl --max-time 20 -i https://api.tastemap.cn/api/v1/sync/pull
预期: 200 application/json {"status":"ok"}; 未登录 sync 为401 JSON
```

DNS API returns403; Chrome Cloudflare tab remains at login. Direct HTTP /health to120.26.235.179 with Host api.tastemap.cn returns404. This does **not** prove the IP serves no other Taste Map business. Do not delete blindly or touch tastemap.cn main website, api-dev or origin-api. Normal shipping Base URL remains https://api.tastemap.cn.

## Offer mapping — no guesses

All60 codes remain unused and six batches unmapped. Original WeChat temp attachments no longer exist. Inventory import timestamps are only2026-09-07 08:51:34.969–.973 UTC, reflecting an import operation rather than download/offer associations. Chrome OfferCode download search has no results; Chrome history database is locked and targeted history search exposed no app metadata; ASC browser login failed. Existing logs/reports do not establish Offer Identifier associations. The spreadsheets skill's read-only/sensitive-data handling was used; no CSV rewritten or code printed.

Please fill only these metadata associations, never redemption codes:

| Batch | Offer reference name | Exact Apple Offer Identifier |
|---|---|---|
| 580777 | to confirm | to confirm |
| 580908 | to confirm | to confirm |
| 580853 | to confirm | to confirm |
| 580922 | to confirm | to confirm |
| 580852 | to confirm | to confirm |
| 580833 | to confirm | to confirm |

Allowed names: 被邀请用户14天会员 / 邀请奖励1 / 邀请奖励2 / 邀请奖励3 / 邀请奖励4 / 邀请奖励5. The protected inventory is `.private/sandbox-offer-codes/inventory.sqlite`; CSV archival copies are in the same ignored directory. Mapping failure keeps allocation locked. Automated operator tests retain exclusive assignment/idempotency, owner binding, qualified reward requirement, failed-not-recycled states, server-backed redeemed state and Sandbox-only guard. Actual code redemption remains untested. Apple transaction evidence identifies an Offer, not a particular secret one-time code.

## One real-device acceptance matrix

Keep results pending until actual iPhone actions are observed. No keys or codes in screenshots/logs. Use the prepared isolated Sandbox build for reward inventory tests; separately prove the normal Release JWS path through formal API after DNS is corrected. Existing isolated-build install report says the iPhone12 was locked; paired availability alone is not installation success.

| # | Test | Required evidence |
|---|---|---|
| 1 | Monthly product load | Actual StoreKit product ID/displayPrice |
| 2 | Annual product load | Actual StoreKit product ID/displayPrice |
| 3 | Monthly Sandbox purchase | Apple Sandbox sheet completed, no real charge |
| 4 | Verified transaction | StoreKit verified result/JWS reaches Native pipeline |
| 5 | Server verification | Apple environment and appAccountToken match correct user ledger |
| 6 | Premium refresh | Authoritative response correlates with UI, not an existing referral/trial grant |
| 7 | Restore | Idempotent transaction and preserved entitlement |
| 8 | Logout/login | Another Taste Map account does not inherit purchase |
| 9 | Invitee14-day Offer | Confirmed mapping, qualified test user, exclusive assignment, real Sandbox redemption |
| 10 | Reward1 Offer | Same evidence for referrer slot1; no code in evidence |
| 11 | Sign in with Apple | Real authenticated session |
| 12 | MapKit pan/pinch | Responsive real-device map |
| 13 | Marker select | Correct restaurant selection |
| 14 | Viewport restore | Preserved camera after back navigation |
| 15 | Location | Permission/result behavior |
| 16 | Camera | Capture and cancellation |
| 17 | PhotosPicker | Selection and cancellation |
| 18 | Visit create/edit/delete | Correct owner data and persistence |
| 19 | Photo upload/retry/delete | Actual R2 lifecycle and no orphan/reappearance |
| 20 | Sync | Actual server acknowledgment and reflected data |
| 21 | Offline/reconnect | Local behavior then correct reconciliation |
| 22 | A→B→A | Auth/cache/data/Premium isolation |
| 23 | Delete does not resurrect | Tombstone survives reconnect/restore |
| 24 | Share Extension | Correct app/account handoff |
| 25 | Referral Universal Link | Link attribution/new signup/first valid Visit; use test environment only |

Before public release, additionally verify real Production transaction/notification lifecycle and correct App Apple ID. Gift Admin activation is optional unless that internal feature is being used.

## Automated artifacts and file scope

Local evidence root: `/tmp/tastemap-production-recovery.PXmKfO`. `gate-deploy.log`, `gate-development-deploy.log`, `post-gate-version.log`, `post-gate-assets.log`, `current-assets-parity.json`, `reclassified-final-tests.json`, `release-jws-build.log`, `local-environment-worker.log`.

Latest completed full regression at report preparation: **1,457/1,457 PASS, zero pending**, TypeScript PASS; focused signing/readiness/commerce/operator/boundary suite58/58. Release iOS compile PASS. Formal native artifact purity49 files PASS;26 Web files match stage/built bytes. These are pre-cutover verification artifacts, not a signed Final RC or real-device smoke acceptance. Shared workspace has concurrent changes and subsequent snapshots may add tests.

Files changed for this task: `worker/appleSignedData.ts` and test; `worker/appStoreCommerceV1.ts` and integration test; `worker/productionReadiness.ts` and test; `worker/index.ts` (Admin patch plus numeric app-ID type); `ios/TasteMap/TasteMap/Services/PremiumCommerceAPIClient.swift`; `StoreKitMembershipPurchaseProvider.swift` (JWS forwarding while preserving concurrent session guards); package.json/pnpm-lock.yaml/tsconfig.worker.json; both Wrangler configs (nodejs_compat); this report and status supersession notices. Existing native isolation/Sandbox scheme/0038/operator changes belong to concurrent work and are not claimed as newly authored here. No source frontend change was made in this task.

## Final gate classification

| Gate | Status |
|---|---|
| WEB TESTS | PASS |
| CURRENT PRODUCTION BASELINE | dd0369b9-26c1-4fe7-a23b-9a56f5887661 |
| PRODUCTION BASELINE | PASS / ADOPTED |
| PRODUCTION REGRESSION | PASS |
| CORE PRODUCTION READINESS | PASS; formal domain health/auth boundary acceptance also PASS |
| GIFT ADMIN READINESS | NON-BLOCKING; optional ID required for activation |
| PRODUCTION PURITY | PASS under behavior/leak rules |
| APPLE SANDBOX SERVER API | PASS credential evidence, not a purchase |
| APPLE PRODUCTION SERVER API | DEFERRED UNTIL APP STORE PRODUCTION;401 cause not certified |
| STOREKIT ENVIRONMENT ARCHITECTURE | PASS automated/routing/signature boundary; real transactions still pending |
| APP STORE SERVER NOTIFICATIONS | PASS; real Sandbox delivery, signed verification, audit and UUID idempotency closed |
| API.TASTEMAP.CN | PASS — public/default DNS, normal curl, IPv4, TLS, Worker ownership and Production Base URL verified |
| SANDBOX OFFER MAPPING | PASS / VERIFIED; six mappings adopted |
| PRODUCTION SANDBOX-OFFER ISOLATION | PASS; 403 sandbox_offer_forbidden preserved |
| NORMAL STOREKIT REAL DEVICE | PASS; frozen real Sandbox single-account loop |
| REFERRAL FIRST-TESTFLIGHT VISIBILITY | FAIL; source guards tested, installed artifact proof pending |
| INVITEE 14D REAL SANDBOX | DEFERRED TO TESTFLIGHT INTERNAL BETA |
| REWARD 1 REAL SANDBOX | DEFERRED TO TESTFLIGHT INTERNAL BETA |
| REWARD 2–5 | DEFERRED TO TESTFLIGHT INTERNAL BETA |
| REAL DEVICE CORE SMOKE | USER ACTION REQUIRED |
| FINAL VISUAL / MAP FEEL | USER ACTION REQUIRED |
| FINAL CUTOVER GATE | CLOSED |
| HYBRID_PRIMARY | NOT YET |
| FINAL RC | NOT YET |
| TESTFLIGHT READINESS | NOT READY; real gates then new cutover archive required |

Only after the true gates pass: cut over, preserve SwiftUI rollback, clean build/stage/signed build/archive, behavior purity and byte parity, full regression/F1-C4/account/entitlement/referral/sync acceptance. All prior pre-cutover archives remain ineligible as Final RC.

## Primary references

- Apple: [TestFlight IAP uses Sandbox](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight/).
- Apple: [TransactionIdNotFoundError4040010](https://developer.apple.com/documentation/appstoreserverapi/transactionidnotfounderror).
- Apple: [Official server library verification](https://github.com/apple/app-store-server-library-node/blob/main/README.md), [SignedDataVerifier](https://apple.github.io/app-store-server-library-node/classes/SignedDataVerifier.html).
- Apple: [Public PKI trust anchors](https://www.apple.com/certificateauthority/).
