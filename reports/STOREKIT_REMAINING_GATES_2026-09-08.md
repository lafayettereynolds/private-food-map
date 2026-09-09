# Remaining StoreKit Device Gates — 2026-09-08

## Frozen real-device acceptance
MONTHLY PRODUCT LOAD: PASS
ANNUAL PRODUCT LOAD: PASS
MONTHLY SANDBOX PURCHASE: PASS
TRANSACTION VERIFICATION: PASS
SERVER ENTITLEMENT: PASS
UI PREMIUM REFRESH: PASS
RESTORE PURCHASE: PASS
NORMAL STOREKIT REAL DEVICE: PASS

Scope: installed com.lafayette.tastemap ReleaseSandbox, isolated Development API, real iPhone17ProMax. Preserve these evidence results independently of later Offer/account gates. Do not repeat purchase or restore. Prior evidence: STOREKIT_SANDBOX_E2E_2026-09-08.md and build/storekit-sandbox-e2e/restore-1547-evidence.json.

## Mapping evidence reconciled
Production deployment task already visited all six ASC Offer pages and downloaded existing batches only to establish filename provenance. Source: /Users/lafayette/Projects/private-food-map-storekit-production-deploy/reports/STOREKIT_PRODUCTION_DEPLOYMENT_2026-09-08.md, Sandbox Offer mapping section. Current isolated inventory source_name / offer_key / offer_identifier matches that report. No redemption secrets read; 60 unused, zero allocated or consumed. mapBatch rejects rebinding; existing mapping retained without mutation. ASC resource UUID is separate from transaction offer identifier (reference name).

| Batch filename suffix | Reference name / transaction Offer Identifier |
|---|---|
|580777|被邀请用户 14 天会员|
|580852|邀请奖励 1|
|580833|邀请奖励 2|
|580908|邀请奖励 3|
|580853|邀请奖励 4|
|580922|邀请奖励 5|

SANDBOX OFFER MAPPING: PASS (reconciled prior direct ASC evidence, not inferred download order).

## Remaining prerequisites
Auth exchange validates signed Apple issuer/audience/nonce and maps provider subject to separate server userID. No ordinary operator route creates a genuine signed-in Apple identity. Sandbox purchase tester is not a second Sign in with Apple identity. A→B→A requires actual second Apple identity on the same test device; no identity bypass or entitlement insertion authorized/performed.
Offer allocation requires existing qualified referral reward with distinct invitee/referrer and qualifying Visit. No reward/assignment is fabricated just to consume codes. B must be registered through A referral before qualification; do not prematurely create B without attribution. Invitee14D and Reward1 require live identity and qualification first.

ACCOUNT ISOLATION: USER ACTION REQUIRED
INVITEE 14D OFFER: USER ACTION REQUIRED
REFERRER REWARD 1: USER ACTION REQUIRED
REWARD 2–5: FAIL (acceptance incomplete until Reward1 E2E; automated coverage alone is insufficient)
STOREKIT DOES NOT OVERWRITE GIFT: PASS
GIFT + STOREKIT COEXISTENCE: PARTIAL (coexistence/reconcile/restore preservation PASS; final expiration UI fallback pending)
SANDBOX OFFER E2E: FAIL (not executed)
STOREKIT REAL DEVICE GATE: FAIL (incomplete)

No Production mutation, code consumption, renderer switch, Final RC or TestFlight upload. Core smoke begins only after these StoreKit gates close.


## Superseded Referral blocking classification — user decision 2026-09-08
Referral two-account Offer E2E is DEFERRED TO TESTFLIGHT INTERNAL BETA, non-blocking for first TestFlight while Referral UI/server entry is disabled. Do not require a second Apple account now. Earlier frozen normal StoreKit PASS remains unchanged. New implementation/deployment/build evidence: REFERRAL_FIRST_TESTFLIGHT_VISIBILITY_2026-09-08.md. Core smoke and final visual acceptance remain required; no final cutover/RC/upload performed.
