# RC blocker closure — 2026-09-08

LATEST: [Adopted Production baseline and two-path device plan](PRODUCTION_BASELINE_ADOPTION_2026-09-08.md). CURRENT PRODUCTION BASELINE dd0369b9-26c1-4fe7-a23b-9a56f5887661: PASS / ADOPTED; previous verified baseline/rollback reference87b45679. Core/regression/purity/API/D1/R2/Notifications/Offer mapping/isolation PASS. The user has approved formal candidate2026090801 for normal StoreKit/core and a separate Sandbox build/Worker/inventory only for invitee14/Reward1. Remaining gates: normal StoreKit, both real Sandbox Offers, critical smoke and final visual/Map feel. No pending DNS/mapping/Notifications/baseline approval. Cutover CLOSED, HYBRID_PRIMARY and Final RC NOT YET, TestFlight NOT READY. All contradictory notices below are historical, superseded evidence.

## Subsequent candidate audit, 04:50 UTC

See [Production candidate audit](PRODUCTION_BASELINE_AUDIT_2026-09-08.md) and `production-baseline-candidate.json`. Retain ede1474e and its verified code-identical secrets successor f8dd5e0f; do not restore the old reference. Candidate audit/purity/regression gates remain FAIL, so no formal baseline or cutover. Fresh public asset parity 28/28; health200; ready503 (admin missing); official API unreachable. Local Admin malformed-auth correction and a migration-fixture forward-compatibility correction pass the final current-workspace suite: 1,433/1,433 plus typecheck. Concurrent Sandbox tests account for the count increase. No Production deployment or reward issuance by this audit. Earlier snapshots below remain historical evidence, not the final current gate state.

Baseline: `feature/hybrid-final-integration`, `f7da080`. Supersedes only remaining-blocker status in `RC_FOUNDATION_RESUMED_2026-09-08.md`; does not repeat its migrations, deploy, archive or Swift gate. No Production writes, real Gifts, TestFlight upload or primary-route changes in this task.

## Automated outcome

Web full suite: **1,425/1,425 PASS, 166 files, 0 failed, 0 pending/skipped**. Original 1,402/1,423: all 21 failures closed; two additional Premium-denial cases added. No test removed, skipped or deferred. No environment/debt waiver. Full result and log: protected operator directory `tastemap-rc-resume-yKGy6yVt`, `blocker-final-tests.json` and `.log`.

Typecheck, formal Hybrid Release build/stage PASS. Signed generic-iOS Release build PASS; codesign deep/strict verification PASS; staged and built app each match all 26 Web files byte-for-byte; existing formal purity scanner PASS (55 app files). This build remains **NATIVE_PRIMARY / pre-cutover**. No new archive, no Final RC claim. Installed-runtime visual acceptance is still pending: compilation and SSR are not a screenshot or iPhone gate.

Shipping fixes: shared Restaurant Detail no longer exposes the forbidden Not Interested action; Discovery's full query panel now consumes all shared rating thresholds rather than `[6,7,8,9]`. No card topology redesign, Map implementation, SyncEngine, route ownership or entitlement policy changes. Development config now explicitly carries the four non-secret StoreKit catalog/environment values; not deployed.

## All 21 original failures: cause and disposition

Test names below are identifying fragments from the original JSON. Each row is closed by executable tests, not a release-debt waiver.

| # | Test | Classification / root cause | Correction and retained guarantee |
|---|---|---|---|
| 1 | Global: editable Discovery filter sheets | Outdated expectation: new panel and shared Premium FilterChoiceGroup replaced inline markup | Assert actual panel wiring, apply/reset/cancel and semantic occasion control; retain city/rating/result filters |
| 2 | Global: Discovery chrome tokens | Outdated expectation: city change extracted into `changeCity` | Assert actual handler, normalization and session invalidation; retain token checks |
| 3 | Map: stays mounted under Detail | Outdated expectation: active expression acquired Premium-overlay exclusion | Require the complete guarded expression; mounting requirement retained |
| 4 | Map: canonical For You snapshot | Outdated expectation: Discovery now fetches its selected-city session instead of reading the Map snapshot | Preserve Map canonical projection/counters; require cityPage source and prohibit overwriting canonical content |
| 5 | Profile: three summary values | Outdated label: wanted label changed from 想去 to approved 想吃 | Exact values, controls and surrounding order retained |
| 6 | Dismissal only on For You | **Product regression:** shared Detail still injected RecommendationNotInterested | Remove forbidden Detail rendering; existing positive For You and negative Detail test pass |
| 7 | Settings: membership/account order | Outdated expectation omitted approved referral and private-directory sections | Exact full section sequence now includes both; none removed |
| 8 | Complete rating thresholds | **Product regression:** new query panel hardcoded only four high scores | Both Hybrid consumers use shared thresholds and label policy, including 7.5 and low ratings |
| 9 | Source: unique restaurants | Outdated math expected repeated-visit averaging | Expected 6.5 from first attributed ratings (8 and 5); repeat visits do not rewrite acquisition experience |
| 10 | Source: platform can be worst | Invalid fixture: sole source equalled overall baseline | Add independent high-score baseline; assert baseline 7 and retain exact worst-source outcome |
| 11 | Source: latest linked name | Same missing relative-baseline fixture | Add background source; retain stable-ID identity and both exact renamed results |
| 12 | Profile: concise Taste CTA | Outdated contiguous HTML expectation after PremiumFeatureLabel wrapper | Require approved CTA, label and Premium semantics; retain forbidden cuisine/emphasis checks |
| 13 | Discovery: five tabs/matching | SSR fixture supplied obsolete content prop; effects do not run in SSR | Assert page loading shell/five tabs separately and render actual shared RecommendationCard with the loaded fixture |
| 14 | Discovery: neutral high matching | Same SSR data-lifecycle mismatch | Real card component fixture; exact neutral matching checks retained |
| 15 | Discovery: high-density topology | Same SSR mismatch, not missing runtime card capability | Actual card checks retain topology, rating roles, action grouping and forbidden markup |
| 16 | Discovery: similar-taste badge | Same SSR mismatch | Actual component preserves author/badge and duplication negatives |
| 17 | Discovery: omitted Swift optionals | Same SSR mismatch | Real card receives omitted fields; missing-data and no-crash checks retained |
| 18 | Discovery: social Visit identity | Same SSR mismatch | Actual card with/without concrete Visit; positive and negative social controls retained |
| 19 | Analytics: five names/anatomy | Fixture lacked authoritative Premium context; null correctly locks reports | Positive fixture explicitly Premium; two additional false/null cases assert no monthly data exposure |
| 20 | Analytics: dedicated monthly report | Missing Premium plus obsolete pre-v2 intro/module structure | Exact M01 page, single heading, history entry, records and poster entry; no overview-tabs regression |
| 21 | Premium factual/settings boundary | SSR cannot resolve membership or product effects; old assertion demanded purchase UI before authorization | Assert honest initial membership loading and no price/plan/restore yet; independent purchase contract retains products→displayPrice, purchase(id), restore, loading/retry and no hardcoded prices |

The source minimum-sample negative test was also strengthened: two four-restaurant sources and a real contrasting baseline, instead of five equal-baseline samples that accidentally passed for another reason. Source UI promises are governed by current canonical product rules, not historical snapshots.

## Live configuration and concurrency evidence

During this audit external work changed the shared documentation and Production Secrets. Those document edits are excluded from this commit; no other task was directed. Initial Apple absence was superseded by a second live settings read: **all three Apple secret_text binding names now exist**. `/ready` confirms `storeKitConfigured=true`, `administratorConfigured=false`, database/photos=true, HTTP503. Presence is not Apple authentication/transaction proof. Do not ask Lafayette to install those three values again.

The other task's catalog report records Sandbox notification-history HTTP200 and Production HTTP401; this task did not re-read or expose the private key. Treat production verification as unresolved, not as successful transactions. No release waiver is inferred from pre-release Apple availability.

`node scripts/rc-blocker-preflight.mjs` is a read-only, credential-free operator probe. It prints DNS, HTTP status/JSON checks, boolean readiness and inventory counts only; never raw HTTP errors/bodies, tokens or codes. A nonzero exit currently correctly means the official API is not ready. Its origin-api probe is diagnostic only; it does not add a shipping fallback or authorize cutover.

## api.tastemap.cn — user action required

Public DNS: A `120.26.235.179`; no public AAAA/CNAME answer. Exact managed record type/proxy/creator cannot be certified from DNS answers: DNS Records API returns403 (OAuth lacks DNS scope). Worker domains API succeeds: origin-api→private-food-map; api-dev→private-food-map-development; apex→fancy-fog-1341. **No api.tastemap.cn custom domain or route exists.** Current API routes only AASA and `/invite/*` on apex. Prior deploy error100117 identifies an externally managed record conflict. Do not attribute its creator without history. Chrome console fallback reaches Cloudflare login, not an authenticated DNS editor.

```text
网站：https://dash.cloudflare.com/
菜单：tastemap.cn → DNS → Records（先查看/导出精确 api 记录）
当前记录：公开 A 答案 120.26.235.179；控制台记录类型、Proxy 和来源须在此核实
删除/修改：仅移除阻挡 api.tastemap.cn Custom Domain 的旧 api 记录；保留导出以便恢复
新值：Workers & Pages → private-food-map → Settings → Domains & Routes
      → Add → Custom Domain → api.tastemap.cn
      由 Cloudflare 创建 Worker 管理的 DNS/证书，不手填另一个 IP
Proxy 状态：Worker Custom Domain 由 Cloudflare 管理/代理；不要建立 DNS-only origin-api 别名
保存后验证命令：curl --fail --max-time 20 -i https://api.tastemap.cn/health
                node scripts/rc-blocker-preflight.mjs
预期：health 200 + application/json + 正确 health body；ready 也须最终200
```

Do not touch apex, api-dev or origin-api records; these have different responsibilities. If the old api record still serves an active dependency, inspect that dependency before removing it. Current reachability from this Mac fails, so no API PASS claim.

## Exact Apple configuration (code-derived)

No longer missing from Production by **name**; validity remains unproven. These are the only server signing credentials consumed by `worker/appStoreCommerceV1.ts`:

```yaml
- ENV NAME: APP_STORE_ISSUER_ID
  PURPOSE: JWT iss for authenticated Apple transaction retrieval
  REQUIRED FOR: App Store Server API; notification-triggered reconciliation
  WHERE USER GETS IT: App Store Connect team issuer ID
  MENU: Users and Access → Integrations → Keys → In-App Purchase (Issuer ID)
  EXPECTED FORMAT: UUID string
  SECRET?: NO (currently stored as Worker Secret for consistent handling)
  CAN CODEX CONFIGURE AFTER USER PROVIDES IT?: YES via authorized CLI, without logging
  CURRENT: Production secret_text binding present
- ENV NAME: APP_STORE_KEY_ID
  PURPOSE: ES256 JWT header kid
  REQUIRED FOR: same authenticated Apple API calls
  WHERE USER GETS IT: active In-App Purchase key
  MENU: Users and Access → Integrations → Keys → In-App Purchase → active key
  EXPECTED FORMAT: Apple-issued key identifier, normally 10 uppercase alphanumeric characters
  SECRET?: NO (currently stored as Worker Secret)
  CAN CODEX CONFIGURE AFTER USER PROVIDES IT?: YES via authorized CLI
  CURRENT: Production secret_text binding present
- ENV NAME: APP_STORE_PRIVATE_KEY
  PURPOSE: ES256 JWT signing, imported as PKCS8
  REQUIRED FOR: same authenticated Apple API calls
  WHERE USER GETS IT: downloaded In-App Purchase .p8 key
  MENU: Users and Access → Integrations → Keys → In-App Purchase → Generate/active key → Download Key
  EXPECTED FORMAT: multiline PEM with BEGIN PRIVATE KEY and END PRIVATE KEY
  SECRET?: YES
  CAN CODEX CONFIGURE AFTER USER PROVIDES IT?: YES from an explicitly supplied local file into Worker Secret; never via chat/Git/bundle/log
  CURRENT: Production secret_text binding present; no value retrieved
```

The official [Apple key instructions](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/generate-keys-for-in-app-purchases) confirm the Integrations → In-App Purchase path and one-time download. Do not create an unrelated Sign in with Apple private key for this server implementation.

Already-configured non-secret Production values: `APPLE_CLIENT_IDS=com.lafayette.tastemap`; `APP_STORE_BUNDLE_ID=com.lafayette.tastemap`; `APP_STORE_MONTHLY_PRODUCT_ID=com.lafayette.tastemap.premium.monthly.v1`; `APP_STORE_YEARLY_PRODUCT_ID=com.lafayette.tastemap.premium.annual.v1`; `APP_STORE_API_ENVIRONMENT=production`; `APP_ENVIRONMENT=production`. Product IDs come from Apps → Taste Map → Monetization → Subscriptions → subscription group/product. Bundle ID is the existing app identifier, not an invented new one.

Architecture conclusions:

- **Server API needed:** fetchVerifiedTransaction re-fetches from Apple's authenticated API before entitlement writes, enforces bundle/product/environment/appAccountToken. No receipt shared-secret env is consumed.
- **Notifications needed for server-driven lifecycle:** existing POST `/api/v1/storekit/notifications`; v2 notification payload is only a transaction-routing hint; authoritative transaction is re-fetched, not trusted from an unverified client/JWS body. No separate notification-secret env. Configuration is an Apple dashboard URL, not a Worker secret.
- **Sign in with Apple verification needed and implemented:** server checks Apple's public JWKS, issuer, configured audience, expiry, nonce and replay. Native identity-token exchange does not use a web OAuth client secret/private key. Do not introduce one merely because Apple is involved.

Notification user setup/confirmation: Apps → Taste Map → General → App Information → General Information → App Store Server Notifications. Production URL `https://api.tastemap.cn/api/v1/storekit/notifications`, Version2. Separate Sandbox URL `https://api-dev.tastemap.cn/api/v1/storekit/notifications`, Version2 **only after that environment is healthy/configured**. Without a Sandbox URL Apple sends Sandbox notifications to the Production URL; current isolation will reject them. See [Apple notification setup](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/enter-server-urls-for-app-store-server-notifications). Dashboard configuration not verified in this task.

## Admin — user confirmation required

`MEMBERSHIP_ADMIN_USER_IDS` still absent. It must contain authenticated **Taste Map users.id** (typically `tm_…`), comma-separated; NOT Apple provider_subject, Apple Account, email, nickname, device ID or arbitrary client header.

Safe lookup: on the intended **Production** account open 我的 → 设置 → 账户与安全 → 登录状态 → Taste Map ID → copy. Existing Native account view reads authenticatedUser.id and explicitly explains this distinction. Confirm the intended account before configuring the Secret. For an authorized operator, verify the copied ID with a parameterized read-only join of `users.id` and `auth_identities.user_id`, requiring provider='apple' and nondeleted user; no token or provider_subject needs to be printed. Never promote the only/first database user automatically. No admin write or Gift issuance performed.

## Sandbox mapping — not provable, do not guess

Private inventory: six batches ×10, **60 unused / 0 assigned / 0 redeemed / 0 failed**, all offer_key/offer_identifier null. Six local CSV copies have no download-origin/date metadata or Offer labels; no original named downloads found in Downloads/Desktop/attachments or Spotlight search. Headerless one-column code content cannot establish Offer identity. No codes printed or mapped.

Only these six mappings need user confirmation; each response should include the Offer name and its exact Apple Offer identifier (not a redemption code):

```text
580777 → [Offer name / Apple Offer identifier]
580908 → [Offer name / Apple Offer identifier]
580853 → [Offer name / Apple Offer identifier]
580922 → [Offer name / Apple Offer identifier]
580852 → [Offer name / Apple Offer identifier]
580833 → [Offer name / Apple Offer identifier]
```

Allowed names: 被邀请用户14天会员、邀请奖励1、2、3、4、5. Name alone is not a substitute for Apple transaction.offerIdentifier used by verification.

All eight synthetic inventory tests pass: unused/idempotent import; mapped+qualified assignment; referrer slot/pending rejection; failed non-recycling/private handoff; atomic rollback; lifetime/revoked rejection; owner/offer/environment validation; replay rejection and redeemed state. Generated synthetic values only; no live code consumed. Git inventory guard PASS. Real assigned/redeemed state remains untested until real-device operation and confirmed mapping.

## Short real-device handoff and diagnostics

**Preparation remains gated:** Development `/health` currently returns500; a live settings read shows only APP_ENVIRONMENT, APPLE_CLIENT_IDS, DB, PHOTO_STORAGE and SYNC_AUTH_MODE — no StoreKit catalog/env or signing credential bindings. Checked-in Development previously lacked catalog/env and this patch supplies only public configuration. Apple secrets and actual server verification must exist in the isolated Development Worker before purchase smoke. Do not solve this by changing Production to Sandbox. Debug uses api-dev; Release uses formal api and rejects environment overrides. No StoreKit configuration fixture or `TASTEMAP_P4H_PREMIUM_UI_TEST` may be enabled during real Apple proof.

1. Codex prepares a signed physical-device Sandbox Debug build with real Apple product IDs, no local StoreKit fixture, no Premium bypass; preflight identifies its API environment. User logs into the intended Sandbox Apple account and Taste Map test account.
2. Open Premium: monthly and annual products both load with App Store-localized prices. Buy Monthly; Codex correlates Apple-verified transaction → same appAccountToken owner → authoritative active membership_entitlements → Premium UI. Restart then Restore Purchase; no duplicate ownership or fabricated unlock.
3. With two eligible test Taste Map accounts and confirmed Offer mapping, use the existing qualification/allocation workflow. User actually redeems one invitee14day code and one reward1 code via private handoff. Codex verifies actual Sandbox offerIdentifier, transaction environment, account ownership and resulting entitlement. Do not count independent referral ledger credit as Apple transaction proof. Reward2–5 rely on slot/isolation automated coverage unless real evidence exposes a slot-specific issue.
4. On the real iPhone run: Apple sign-in; Map pan/pinch/marker/detail/back viewport; Location fresh fix/denied/reduced; Camera and PhotosPicker permission cancel/allow; Visit create/edit/delete; photo upload then offline retry/delete; sync/restart; A→B→A; repeat pull after deletion (no resurrection); Share Extension cold/warm; Universal Link/referral installed/cold/warm. User performs device gestures and permissions; Codex diagnoses outcomes and repairs.

Capture recipe: connect iPhone to Xcode/Console, filter process TasteMap and subsystem `com.lafayette.tastemap`. Reuse AuthSession, Sync and SyncEngine categories and Settings' structured sync diagnostics (stage/category/status/duration/retry/final disposition). Do not alter SyncEngine. Log only step/time/build/environment/operation/error code/expected vs actual state in the shared evidence sheet; raw auth tokens, Apple JWS, precise GPS, photos and code strings never enter reports.

For a location-specific defect only, opt into Debug `TASTEMAP_LOCATION_DIAGNOSTICS=1`: it prints actual coordinates, age, horizontalAccuracy and simulated/accessory flags; those traces stay private locally and the flag is removed afterwards. Map frame diagnostic flag likewise stays Debug-only. Other UI/permission steps use screenshots/video plus these existing diagnostics, not a new persistent telemetry service. Screenshot/redact IDs and private content before sharing.

Evidence row per step: build hash; device/iOS; Native/React renderer; Development/Production; account alias A/B; UTC time; expected; actual; sanitized error category; screenshot filename; PASS/FAIL. Blank/unexecuted means **USER ACTION REQUIRED**, never PASS. Real photo upload/retry/delete and R2 owner isolation are still gates, despite a successful R2 HEAD.

**TestFlight caveat:** [Apple confirms TestFlight purchases use Sandbox](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight/), while the current signed Release points at a Production-only verifier. An isolated, approved TestFlight/Sandbox verification path is not proven by the Debug plan. No relaxation of Production isolation or hidden origin-api fallback is introduced here. This must be resolved/verified before claiming TestFlight commerce readiness.

## Design system / final gates

Core UI: existing shared filters/buttons preserved; Food & Dining: unchanged; Canonical templates: Detail negative action rule and complete Discovery rating policy restored at shared owners. Browser/Capacitor share React implementation; Native rollback retained. No new visual tokens/default-SwiftUI redesign. Runtime visual acceptance remains pending, not a screenshots PASS. No route readiness promoted.

```text
WEB TESTS: PASS
API.TASTEMAP.CN: USER ACTION REQUIRED
APPLE SERVER CONFIG: USER ACTION REQUIRED (bindings present; production verification/notifications unresolved)
ADMIN CONFIG: USER ACTION REQUIRED
SANDBOX OFFER MAPPING: USER ACTION REQUIRED
STOREKIT REAL DEVICE: USER ACTION REQUIRED
REAL DEVICE CORE SMOKE: USER ACTION REQUIRED
FINAL CUTOVER GATE: CLOSED
HYBRID_PRIMARY: NOT YET
FINAL RC: NOT YET
TESTFLIGHT READINESS: NOT READY
```

After all gates close, perform authorized cutover and create a new unique Final RC with clean Web/stage/build/signed device/archive/purity/byte parity/final regression. Keep old SwiftUI rollback. Existing Pre-Cutover archive is not reusable as Final RC.
