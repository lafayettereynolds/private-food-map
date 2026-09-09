# StoreKit Sandbox end-to-end closure — 2026-09-08

## Decision

**StoreKit Sandbox is not yet PASS. TestFlight acceptance gate remains CLOSED.**
No actual Sandbox purchase or offer redemption was performed in this task. The Development transaction/assignment baseline is empty. Credentials, builds and automated tests are preparation evidence only. Rows marked FAIL below mean the required real-device evidence is absent, not that a purchase was observed to fail.

## Configuration audit

- Monthly: `com.lafayette.tastemap.premium.monthly.v1`; Annual: `com.lafayette.tastemap.premium.annual.v1`. Exact matches to user-supplied App Store Connect screenshots, subscription group 22338645, same level. China prices in screenshots: CNY 8/month and CNY 80/year. Real iPhone StoreKit prices have not been observed.
- Both products feed the existing authoritative Premium entitlement projection. The ledger can preserve different monthly/annual source labels without creating different access tiers. No new Apple products or fake transactions were introduced.
- React membership presentation consumes authoritative entitlement `isPremium`; profile tier is not an alternative grant. Native commerce refreshes PremiumEntitlementService after server reconciliation.
- Normal Release uses Production API configuration. Dedicated `TasteMap Sandbox TestFlight` / `ReleaseSandbox` uses a compile-time Development endpoint and no DEBUG condition. This archive is only for Sandbox testing, not public App Store submission. No automatic Production-to-Sandbox retry was added.
- Development keychain auth, entitlement cache, SwiftData and social outbox namespaces are separated from Production. Same-account A→B→A async purchase races are guarded by a session generation, not only user ID.
- Existing Apple key retained; three server secrets installed on Development as well as the previously configured Production worker. Sandbox credential validation HTTP 200 is not purchase verification. Production HTTP 401 remains **not finally verified before release; recheck before public release**, without key rotation.

## Changes and deployed scope

- `StoreKitMembershipPurchaseProvider.swift`: session-generation guards around purchase, restore, configuration, current entitlements and reconciliation; signed-out restore fails before StoreKit sync; stale results cannot finish/update another session.
- `PremiumEntitlementService.swift`: disables development Premium override for the isolated development-e2e runtime.
- `TasteMapApp.swift`, `AppEnvironment.swift`, `KeychainCredentialStore.swift`, `PremiumEntitlementCache.swift`, `SocialCollaborationOutbox.swift`: Sandbox build routing and separate local persistence namespaces.
- Xcode project and schemes `TasteMap Sandbox E2E`, `TasteMap Sandbox TestFlight`: explicit test launch/archive configurations. Bundle identifier, Team, product IDs and normal Release signing retained.
- `0038_sandbox_offer_assignments.sql`: Development-only metadata ledger; no offer code secrets. User/reward/offer/environment, assignment state and unique transaction binding.
- `worker/appStoreCommerceV1.ts`: Sandbox offer transactions require a matching assigned owner/offer. Conditional original-transaction reservation prevents competing redemptions; existing Apple entitlements remain independent of reward revocation. Missing appAccountToken is rejected.
- `scripts/sandbox-offers.mjs`: safe Development ledger refresh, metadata publish before handoff, and server-evidence-driven redemption sync. Existing local private code pool remains outside App/Worker resources.
- Tests in `Task08PremiumCommerceTests.swift`, `worker/appStoreCommerceV1.integration.test.ts`, `scripts/sandbox-offers.test.js`; formal Release scanner also rejects Sandbox configuration markers.
- Development Worker version deployed: `be6d51c3-ddf4-4336-b1d8-92ab093a13a2`. Pending Development migrations through 0038 applied. Production was not deployed by this closure task. Other work is concurrently present in the checkout; this report does not claim ownership or deployment of those changes.
- Development health HTTP 200; forged `X-Taste-Map-Test-User` requests rejected with HTTP 401. Real authenticated accounts are required.

## Automated evidence

Evidence directory: `build/storekit-sandbox-e2e/` (local artifacts, not a secrets handoff).

- `server-tests-final.log`: 48 tests in 5 files passed. Covers commerce, gift/referral precedence, idempotency, Sandbox assignment ownership and concurrent reservation, private operator inventory.
- `ios-tests-final.log`: 36 tests in 4 suites passed. Commerce/session isolation, entitlement foundation, auth and test runtime isolation. These are not real StoreKit transactions.
- Normal Release and dedicated Sandbox archive build logs and final purity/secret scan results are stored alongside this report's evidence directory.
- Production gift annual/lifetime, Apple entitlement revoke/expiry and remaining reward precedence have automated coverage. No product rule was changed to force a test result.
- All six logical referral keys use the same tested ownership/mapping pipeline. Actual downloaded batch-to-Offer identifiers remain unproven, so Reward 2–5 mapping cannot be marked PASS.

## Offer mapping and security boundary

60 private codes remain unused, six batches unmapped; no code was consumed, emitted in this report or bundled. The one pending user question asks for six lines containing CSV suffix, offer name and exact Apple Offer Identifier. Suffixes: 580777, 580833, 580853, 580852, 580908, 580922. Do not guess chronological mapping.

After mapping: refresh-ledger → assign qualified reward → publish assignment metadata → private handoff → actual Apple redemption → server verified transaction → refresh-ledger → sync-redemption. Failed codes never return to the pool. Repeated assignment returns the original assignment.

Apple transactions identify the Offer, not an individual one-time code. `redeemed` means matching verified offer evidence for the exclusive assignment; it is not an Apple per-code inventory receipt. Server admission blocks an unassigned Taste Map user from gaining that entitlement, but cannot prohibit sharing/entering a bearer code in Apple's redemption UI. A matching offer alone must not be presented as cryptographic proof of which code was consumed. Missing appAccountToken remains a real-test blocker, not permission to auto-bind a purchase to whoever first submits it.

## Minimum real-device run

1. Unlock the paired iPhone 12 and keep it connected for installation. The initial attempt failed because the phone was locked; no successful install/launch is claimed from that attempt. Use the prepared Sandbox build, not the normal Production build.
2. Development-signed build: begin a purchase to expose the Sandbox sign-in prompt if needed. Sandbox controls: **Settings → Developer → Sandbox Apple Account → Sign In**. No need to sign out of primary iCloud. For TestFlight Sandbox-account controls, Apple separately documents signing out of **Settings → [Apple Account] → Media & Purchases**, then signing in under Developer; do not sign out of iCloud itself. A China Sandbox storefront is needed to verify CNY prices.
3. In Taste Map, sign into actual test account A, open **Settings → Taste Map Premium**, record both loaded products/prices, tap Monthly, verify Apple sheet indicates Sandbox, complete purchase and return. Capture Premium status and expiry. Annual needs product loading and mapping verification, not a second purchase through the same pipeline this round.
4. Tap **Restore Purchase** on that page. Log out A, log in actual account B, verify B does not inherit A's Apple entitlement; then return to A and restore. Changing only the Sandbox Apple Account does not change Taste Map's Sign in with Apple identity. Do not call two sessions the same/different account without confirming server user identity.
5. Prepare real qualified referral accounts: B as referrer and new A as invitee, using the existing invite registration flow and a real first saved visit. Avoid claiming trial/referral rewards before the initial Free-to-Monthly UI test if they would hide that transition. Respect existing reward settlement rules; do not manufacture rewards in SQL.
6. After confirmed mapping and exclusive code handoff, redeem invitee 14-day and referrer reward 1 on their assigned accounts: **Settings → Developer → Sandbox Apple Account → Manage → Initiate Transaction → Offer Codes**. Return to Taste Map and restore/refresh. No need to consume Rewards 2–5 absent an implementation difference.
7. Collect actual environment, product ID, original transaction ID, expiry/revocation, verified state, server user binding and replay result from the server ledger, then correlate UI refresh. Existing app-owned referral Premium alone cannot prove that Apple redemption succeeded.

Apple references: [Sandbox testing](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox), [outside-app purchases](https://developer.apple.com/documentation/storekit/testing-purchases-made-outside-your-app), [Offer Codes](https://developer.apple.com/documentation/storekit/supporting-offer-codes-in-your-app), [pre-release Production API discussion](https://developer.apple.com/forums/thread/806452).

## Acceptance status before real-device run

| Required item | Status | Evidence boundary |
|---|---|---|
| APPLE SERVER CREDENTIAL | PASS | Sandbox HTTP 200 only |
| MONTHLY PRODUCT LOAD | FAIL | Real iPhone loading/price absent |
| ANNUAL PRODUCT LOAD | FAIL | Real iPhone loading/price absent |
| MONTHLY SANDBOX PURCHASE | USER ACTION REQUIRED | Apple sheet not completed |
| TRANSACTION VERIFICATION | FAIL | No actual Sandbox transaction |
| SERVER ENTITLEMENT | FAIL | No actual purchase-derived result |
| UI PREMIUM REFRESH | FAIL | No correlated real UI proof |
| RESTORE PURCHASE | FAIL | Real restore pending |
| ACCOUNT ISOLATION | FAIL | Automated checks pass; real A/B/A pending |
| INVITEE 14D OFFER | USER ACTION REQUIRED | Mapping and actual redemption pending |
| REFERRER REWARD 1 | USER ACTION REQUIRED | Mapping and actual redemption pending |
| REWARD 2–5 MAPPING | FAIL | Downloaded batch mapping unconfirmed |
| GIFT + STOREKIT PRECEDENCE | PASS | Automated entitlement precedence only |
| SANDBOX / PRODUCTION ISOLATION | PASS | Separate backend, strict verifier, local namespaces, dedicated build |
| STOREKIT SANDBOX | FAIL | Three-layer real closure incomplete |
| STOREKIT TESTFLIGHT GATE | CLOSED | Do not confuse prepared archive with acceptance |

## Design System Compliance

No visual redesign, navigation restructuring, new purchase price placeholder or new product tier. Existing Premium and referral entry points retained. Device UI validation is pending; successful compilation is not visual acceptance.

## Final artifact verification

- Final normal Release build: **BUILD SUCCEEDED** (`release-build-final.log`).
- Final Sandbox Release archive: **ARCHIVE SUCCEEDED** (`testflight-archive.log`). Archive path: `build/storekit-sandbox-e2e/TasteMapSandbox.xcarchive`. Not uploaded to TestFlight.
- `final-artifact-scan.json`: both App artifacts scanned, 55 files each, zero matches for the 60 actual private codes, Apple PEM/DER key, issuer/key identifiers. Neither executable contains the debug Premium override. Only the Sandbox executable contains the Development endpoint.
- `release-purity-final.log`: normal formal Release scanner passed.
- `release-resources-final.log` and `sandbox-resources-final.log`: staged and built 26 Web files match current formal resources byte-for-byte.
- `offer-git-guard-final.log`: private code Git guard passed.
- `device-install-final.log`: retry with the final Sandbox archive was again rejected because the paired iPhone remained locked (CoreDevice 10003 / RemotePairing 1016). No device installation or runtime acceptance is claimed. Unlock is required before the next install attempt.

## Connected device follow-up — 13:25 local time

- USB-connected target is iPhone 17 Pro Max (CoreDevice 60BBB934-D441-53FB-B8CF-0E3DB5878C4D), not the older paired iPhone 12. Final Sandbox archive installed successfully (`device-install-connected.log`).
- Initial launch attempts returned a generic signature/entitlement/trust rejection. Device screenshot showed no developer trust entry. Local deep signature verification passed, App and extension identifiers/Team/entitlements match their profiles, both profiles include this device, and the signing certificate is included and unexpired. No signing configuration was changed.
- A stale Taste Map process used an older installation path. After terminating that process, launch succeeded (`device-launch-after-stop.log`). The new PID 12155 uses the newly installed container 6A107F1E-74E1-4369-BF8E-741A9627C188 (`device-processes-after-launch.json`). This proves launch of the intended installed artifact, not Premium screen rendering or product loading.
- No purchase, restore or redemption initiated. No HYBRID_PRIMARY switch, TestFlight upload or code consumption.
- Mapping inspection: current Chrome App Store Connect tab is logged out (authResult=FAILED); Chrome download search for OfferCode has no results. Six original WeChat CSVs have only quarantine metadata, archived copies only provenance metadata, with no source URL/Offer metadata. Candidate mapping remains unconfirmed, no inventory mutation.
- To obtain objective mapping, open each existing Offer under App Store Connect → Taste Map → Subscriptions → Taste Map Premium → owning subscription → Offers/Offer Codes → offer reference name. Read the exact Reference Name (used as Offer Identifier for offer-code transactions); do not substitute subscription Product ID, group ID or a promotional-offer identifier. In that Offer's Sandbox Codes section, inspect/download the existing batch (never create codes). Record which filename suffix is produced from that row, along with its quantity/creation/expiration metadata. If the UI exposes no Batch ID label, do not invent one or equate the subscription ID with it. Re-downloading the existing batch preserves the direct Offer-page-to-file provenance without sharing actual code values.

## Real-device Premium screen and single-account constraint

The user's 13:28 real-device screenshots show the Native primary Premium settings/paywall rendered, with `赠送资格 · 长期有效`, a trial claim and Restore, but no Monthly/Annual catalog. Source audit confirms active Premium/grace-period users take `activeMemberActions` and `loadProductsIfNeeded` returns before StoreKit product loading. This is not observed StoreKit product-load failure. Screenshot evidence does not establish a new Apple entitlement.

User has only this account/device. Preserve its grant and all production rules. A compile-time-only `TASTEMAP_SANDBOX_BUILD` catalog entry now reuses the existing productSection and exact product/provider/purchase/restore/server-authority pipeline for an active member. It appears as `Sandbox 订阅测试`; entering it only loads real products. Purchase still requires the existing explicit purchase action and authenticated server configuration. It creates no entitlement, bypass, fake transaction or new SKU. Normal Release excludes the entry and retains the original active-member behavior. Formal Release scanner rejects its accessibility marker.

Single-account scope: product loading, real Monthly purchase, verification, existing Gift + Apple coexistence, Premium refresh and same-account restore can proceed. Free→Premium transition, A→B→A and real invitee/referrer dual-user redemption remain unverified without a second genuine identity/qualified referral. Do not consume codes against manufactured eligibility or reinterpret a changed Sandbox Apple Account as a changed Taste Map user. Latest Development snapshot has zero Apple transactions; all 60 codes remain unused.

Design System Compliance for this test entry: Core control reuses the existing member-action group and shared 44-point token; Food/hamburger visuals unchanged; canonical Premium section order and Native primary renderer unchanged; one existing productSection reused, no second purchase renderer. Browser/Hybrid product surfaces and extension have no matching Sandbox operator entry and are unchanged. Real-device appearance of the rebuilt entry remains a user verification step; build success alone is not UI acceptance.

Sandbox catalog follow-up completed at 13:38: Sandbox ARCHIVE SUCCEEDED and normal Release BUILD SUCCEEDED. Sandbox executable contains premium-sandbox-catalog; normal Release purity scan rejects/does not contain it. Final secret scan again found zero sensitive matches across both 55-file artifacts, and 26 staged/built Web resources match. Updated archive installed and launched successfully on the connected iPhone 17 Pro Max; catalog-launch.json records PID 12201 and the new installation container 537527A7-69BD-41FF-A9AE-3CA7E8F62461. No purchase triggered. User's next step is Settings → Taste Map Premium → View Premium Benefits → Sandbox 订阅测试, then screenshot real Monthly/Annual products without tapping 开通 Premium. Actual product-load/visual acceptance remains pending.

## Real-device product loading — 13:39 screenshots

User-supplied screenshots `5281bf9038244d30bd90fda3d4383235.jpg` and `bb42e7f3ac8c6755924d9c6ae180da09.jpg` show the installed Sandbox catalog on the real iPhone, with Annual US$11.99 / yearly renewal and Monthly US$0.99 / monthly renewal, explicit purchase and restore controls. MONTHLY PRODUCT LOAD = PASS and ANNUAL PRODUCT LOAD = PASS for this observed USD catalog. China storefront CNY 8/80 remains unverified; USD currency alone does not prove a specific country or authenticated Sandbox Apple Account. No purchase-sheet or transaction evidence yet. Annual is initially selected by existing UI logic; next manual step must explicitly select Monthly before opening the Apple sheet. Do not confirm until the Apple sheet/account is identified as Sandbox. This supersedes the earlier pre-device product-load pending rows, not the overall StoreKit/Gate decision.

## First reported Monthly purchase — server closure pending

User reports Sandbox account signed in and Monthly purchased successfully. A fresh Development D1 export completed successfully (`ledger-after-monthly-purchase.log`), but app_store_transactions still contains zero rows. No actual transaction metadata, Apple verification success, binding or purchase-derived entitlement can be marked PASS from this observation. User does not remember the in-app result message. Do not buy again. Next diagnostic step is the existing Restore Purchase action on the same Taste Map/Sandbox accounts, which resubmits current verified StoreKit entitlements through the normal server reconciliation path; capture the resulting UI message and then refresh server evidence. Overall StoreKit Sandbox remains incomplete.

## 13:50 restore failure and safe Sandbox diagnostic

Actual device screenshots show `Apple 签名验证失败。` after restore. The deployed Sandbox module contains this exact server-side error in signedDataBoundary wrapping Apple's SignedDataVerifier; it is distinct from the local iOS signing/trust issue. No real transaction verification/entitlement PASS is claimed.

Fetched the actually deployed Development module instead of deploying the concurrently modified working tree. Applied a minimal diagnostic-only patch to that same module: retained all signature/chain/online checks and error rejection, but surfaced the Apple verifier's bounded numeric status (0–7 or unknown) and a fixed allowlist cause class (TypeError/Error/NotSupportedError/FetchError/none) in the generic error. No JWS, transaction token, password, private key or Offer Code is logged or included. No Production deployment or credential changes. All existing Development bindings were checked equal before/after. Deployment identifier: b74eb9d5aec14ad297080dd35699f49c; evidence signature-diagnostic-deployment.json. Two preceding rejected uploads failed module-type validation and did not establish a new running version; corrected ES-module MIME was accepted.

This is diagnosis, not a signature-validation fix. Next required device action: dismiss any outstanding Apple account dialog as appropriate, retry Restore once on the same Sandbox account, and capture the full bounded diagnostic result. Do not repurchase, clear transaction history, rotate keys, disable OCSP/signature validation or consume offer codes to work around this failure.


### 14:05 real-device signature failure: OCSP transport correction

User screenshot reports `invalid_apple_signed_data_s2_TypeError`; existing lifetime gift is not purchase evidence. Deployed Apple SDK calls node-fetch default export, but Wrangler automatic CommonJS shim omitted that export and the native Response lacked SDK-required buffer(). Added worker/appleNodeFetch.ts with native fetch, timeout, and binary buffer compatibility; explicit alias in both Wrangler source configurations. Production was not deployed.

Only the transport shim in the pinned, previously deployed Development module was changed, avoiding unrelated working-tree changes. Deployment 4c5d3e8a0de248fd90bb4190c7bf61d2, all existing bindings preserved; /health HTTP 200. Apple signature, chain, OCSP and entitlement checks remain enabled; no key rotation.

Validation: 12 targeted tests pass; local Workerd with the actual Apple SDK reaches fetch, preserves HTTP503 rejection, and reads binary response while still rejecting deliberately invalid OCSP DER. These probes are compatibility evidence, not an actual Apple transaction verification PASS. Runtime result: build/storekit-sandbox-e2e/ocsp-runtime-result.json.

Next required device action: Restore Purchases once and capture the resulting message. No repeat purchase, no Offer redemption. Real transaction verification, authoritative entitlement and UI closure remain unverified; StoreKit Sandbox is not PASS and TestFlight gate remains CLOSED.


### 15:09 screenshot: wrong installed app identified
Device process evidence at 15:11 shows only QA container CE4B6EB6-553C-49C3-A715-69D82C9AC286 running (com.lafayette.tastemap.qa, build 906.27). Original Sandbox app com.lafayette.tastemap remains in container 537527A7-69BD-41FF-A9AE-3CA7E8F62461. Launched correct Sandbox bundle successfully at 15:11:50 without purchasing. QA screenshot generic error is not evidence of Sandbox transport-fix result. Refreshed Development ledger; transaction count: 0. Await restore on correct app.


### 15:23 real Sandbox verification evidence
Fresh Development ledger now contains 12 distinct monthly Sandbox transactions, one original subscription chain, one user, verification_source app_store_server_api, no revocations. Purchase begins 13:47:23 CST; final expiration 14:47:23 CST; server verified records 15:12:29–15:13:03 CST. One app_store_monthly entitlement exists with that expiration and lifetime admin_grant is preserved on the same user. No duplicate entitlement across these renewal transactions. User restore screenshot at 15:23 says no restorable purchases, consistent with currentEntitlements excluding expired subscriptions. Actual signed transaction/server verification PASS; monthly entitlement persistence PASS, but active paid entitlement UI refresh/active restore and replay test remain pending. Do not treat lifetime gift UI as subscription activation proof. StoreKit overall gate remains CLOSED pending active closure, account isolation and Offers.


### 15:39 new Monthly purchase verified while active
User screenshot shows Apple success dialog Environment Sandbox and actual CNY monthly 8 / annual 80 catalog. Fresh ledger at 15:41:24 CST confirms monthly purchase 15:39:13, server verification 15:39:19.352 via app_store_server_api, expires 15:44:13, not revoked. Total transactions 13. Existing single app_store_monthly entitlement updated to new expiration; admin_grant lifetime retained. Evidence purchase-1539-evidence.json. Purchase + server active entitlement PASS; await dismissing Apple dialog and capturing app success/restore completion before marking UI/restore PASS. Overall gate remains CLOSED.


### 15:47 Restore Purchase real-device PASS (single-account scope)
User screenshot explicitly shows 购买已恢复并由服务器重新验证. Earlier 15:42 purchase success UI and 15:43 App Store monthly status supply purchase UI closure. Fresh Development ledger at 15:50:38 CST shows renewal purchased 15:44:13, expiring 15:49:13, verified 15:47:30.882 by app_store_server_api. Previous 15:39:13 transaction was reverified at 15:43:57.028. Total 14 distinct transaction IDs, one original chain and one user, still exactly one app_store_monthly entitlement, lifetime admin_grant preserved on same account. Additional transaction is renewal, not duplicate grant. Evidence build/storekit-sandbox-e2e/restore-1547-evidence.json.

Confirmed real device: CNY monthly8/annual80 product load, Monthly Sandbox purchase, verification, authoritative entitlement persistence, monthly Premium UI refresh, same-account Restore and no duplicate grant. Annual actual purchase not exercised. A→B→A isolation remains untested (only one Taste Map identity); Offer mapping and invitee/reward1 redemption remain unresolved. Gift lifetime coexistence observed; full gift revoke/expiry precedence matrix not established by this observation. Normal purchase/restore loop PASS; overall requested Sandbox acceptance remains incomplete, TestFlight gate CLOSED. No further Monthly purchase is required for this loop. No Offer code consumed.


## Superseded Referral blocking classification — user decision 2026-09-08
Referral two-account Offer E2E is DEFERRED TO TESTFLIGHT INTERNAL BETA, non-blocking for first TestFlight while Referral UI/server entry is disabled. Do not require a second Apple account now. Earlier frozen normal StoreKit PASS remains unchanged. New implementation/deployment/build evidence: REFERRAL_FIRST_TESTFLIGHT_VISIBILITY_2026-09-08.md. Core smoke and final visual acceptance remain required; no final cutover/RC/upload performed.
