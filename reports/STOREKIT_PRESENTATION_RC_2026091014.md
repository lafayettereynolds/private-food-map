# StoreKit presentation / latency — 1.0 (2026091014)

## Scope and source

- Independent branch: `fix/storekit-presentation-2026091014`.
- Frozen 1013 source: `5f88d838e0da4c29c4750b48048ca9b19f331610`; no newer integration changes imported.
- 1013 archive, uploaded build and source are preserved.
- No Worker, Production data/configuration, migration, authentication lifecycle,
  membership policy, raw ratings, Sync, photos or UGC changes.
- Normal App Store Connect distribution; internal group only, no review submission.

## Findings / minimal correction

Both product prices already passed through `Product.displayPrice`. There was no
USD fallback or manual currency formatter on the formal purchase path. The exact
runtime cause of the reported USD UI / CNY Sheet difference is not yet proven.
Missing Storefront invalidation and independent display/purchase product loads
were confirmed source defects. No claim is made that a fixture proves CHN pricing.

Native now retains actual StoreKit Products in one in-memory catalog. Cache hits
do not invoke Product.products again; a missing product or Storefront invalidation
reloads. Storefront is checked at lookup and after load, and Storefront.updates
invalidates the cache, reloads it, and emits an empty premium.productsChanged
event. Revision checks reject stale in-flight results, including after invalidation.
Empty/failed loads remain retryable. No prices or catalog are persisted on disk.

The shared Premium page commits product prices independently from entitlement
status and trial eligibility. Existing product DTOs and exact localized strings
are retained. Native rollback consumes the same cache and invalidation notification.
Page composition, hamburger, renewal copy, buttons and return flow are unchanged.

Live `/api/v1/storekit/config` readiness validation is deliberately retained before
purchase, including its product allowlist, appAccountToken and session generation.
This minimal delta removes the redundant StoreKit query, not the server security
gate. Transaction verification, server reconciliation, finish and subsequent
entitlement refresh are unchanged. A failed readiness request never opens purchase.

Release-safe diagnostics record country, public product ID/displayPrice, HIT/MISS,
preload duration, and provider-entry/tap-to-purchase-invocation milliseconds.
Optional UI tap timestamp is finite/range checked and diagnostic-only. No Apple ID,
tokens, receipts, transaction payload or account token is recorded. This measures
invocation, not Apple's eventual Sheet appearance; Sheet latency requires video
or physical-device timing.

## Automated evidence

Evidence directory: `.private/storekit-1014` (ignored, not bundled).

- Initial Native targeted: 47/47, five suites, no fail/skip/pending. Includes cache,
  account A→B→A, readiness rejection, logout, entitlement and credential lifecycle.
- Web/Worker release selection: 205/205, no fail/pending. Includes StoreKit backend,
  membership/auth, Hybrid contracts, adapter and Premium return/placement.
- Swift bridge: 43/43, no failure.
- Web and Worker TypeScript: PASS (formal staging).
- Formal Web build / stage: 26 files byte-identical.
- Actual shared React component, isolated Chromium harness: PASS for both prices
  before delayed status/trial; Storefront refresh; stale-response fence; both
  purchase actions and cancellation. Images are explicitly fixture-only, not ASC
  price or physical-device acceptance.
- Native final rerun: 47/47 PASS, no failures/skips. A prior rerun exposed a
  first-load Storefront transition cancellation; the provider now retries that
  invalidated lookup at most three times while respecting caller cancellation.
  The existing readiness and A→B→A assertions were not changed.
- Signed Archive/export/purity/upload: pending at source freeze.

## Design system compliance

Core UI: existing plan/loading/button primitives retained. Food/Dining: approved
Premium hamburger unchanged. Canonical Premium page template/order unchanged.
No new product renderer, CSS scale, duplicate paywall or default-SwiftUI redesign.
Affected consumers: shared Browser/Capacitor Premium page, Native rollback paywall,
typed Native adapter/runtime and shared StoreKit provider. Extensions have no
purchase UI. Test fixture strings never enter formal resources.

## Real-device gate (not replaced by automation)

Install 1014 via TestFlight without uninstalling, clearing data, switching account
or performing container restores. Verify current build/account and queue first.
Record Monthly and Annual actual displayPrice, CHN Storefront diagnostic, and
currency shown by Apple's Sheet. Opening a Sheet is sufficient; do not confirm a
new purchase. Record tap→Sheet seconds; cancel, kill/reopen, then recheck both prices.
1013 numeric before-latency was not measured, so it remains UNKNOWN rather than
inventing a comparison. Source cache tests do not prove Apple network latency.

FINAL APP REVIEW CANDIDATE: NO — pending same-build device verification.

## Signed release and ASC completion — 2026-09-11

- Frozen source commit: `5f02a6ce6e017386787c1d6ae2a8e30b5bc5bd97` (pushed).
- Source fingerprint: `17965332be278b7441daf670a4cd4d622fb5ccb48abf3f5d63597a99ea3ae035`, 2162 tracked files.
- Archive: `.private/storekit-1014/TasteMap-2026091014.xcarchive`, Release compile/archive PASS.
- Exported IPA: `.private/storekit-1014/distribution/TasteMap.ipa`.
- Exported IPA SHA-256: `fb3b949798454c98e380d36fca698f4c84944879dcad4d3c460941435426a986`.
- Archive and export identity/capability audits: PASS for main app and Share Extension.
  Archive uses automatic development signing, then export re-signs for App Store
  distribution. Both exported targets have get-task-allow=false and beta-reports-active=true.
- Archive and export formal resource parity: 26/26 byte matches each.
- Archive and export Production purity: PASS, 55 app files / 26 signed Web files;
  Production API, no Development endpoint/fixture/bypass/secret/private path.
- Exact exported source commit/fingerprint match frozen source; no source changes during archive/export/upload.
- Normal ASC upload succeeded at 10:57:39 Asia/Shanghai, 2026-09-11.
- ASC build ID: `1134b982-5126-4163-84dc-c3fb7f1ecc44`.
- Fresh ASC read: version 2026091014, processingState=VALID,
  buildAudienceType=APP_STORE_ELIGIBLE, internalBuildState=IN_BETA_TESTING.
- Only related group: Internal Testers `6a12949a-c19a-413f-bd1b-9f305b1a05be`.
  Existing group isInternalGroup=true, hasAccessToAllBuilds=true.
- testFlightInternalTestingOnly=false. No External group, public link or review submission.
  externalBuildState=READY_FOR_BETA_SUBMISSION denotes eligibility, not distribution.
- Latest same-branch release selection: 205/205 Web/Worker PASS; Native 47/47 PASS;
  bridge 43/43 PASS; TypeScript PASS. No skipped/relaxed affected assertions.
- No Production service/data changes, no app-container operations, no device install,
  no purchase confirmation and no account switch in this task.

### Physical-device boundary

After ASC became ready, iPhone Mirroring connection was attempted. Its actual
state remains `iPhone使用中 / 锁定iPhone以连接`. Thus 1014 TestFlight installation,
CHN storefront, real Monthly/Annual price, Sheet currency, tap→Sheet seconds and
kill/reopen checks are NOT RUN. The user has been asked to lock the iPhone 17 Pro Max.
Do not label these PASS or use fixture ¥8/¥80 as actual production prices.
1013 remains preserved. APP REVIEW CANDIDATE remains NO until these gates close.
