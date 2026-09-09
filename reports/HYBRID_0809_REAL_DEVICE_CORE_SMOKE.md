# Hybrid 0809 real-device core smoke

Device: iPhone 17 Pro Max, CoreDevice 60BBB934-D441-53FB-B8CF-0E3DB5878C4D.
Scheme Taste Map Private; configuration DebugPrivatePreview; renderer HYBRID_DEVELOPMENT; build 2026090809.
Fingerprint f173901634299d13b41fb9dd2d3a3489f5b93dde4c48c032eff0fb3cc427e32f. Private Development API; preserved local store. This is not a Production RC.

## Established evidence
- Installed build readback: 0809.
- Original data restored: user confirmed; original 27 restaurant and 24 visit UUIDs remain present.
- Current diagnostic capture: 20 entitlement refresh_verified, five sync start/end pairs, no captured auth/discovery errors. This proves those diagnostics only, not all discovery content or sync reconciliation.
- Normal StoreKit real-device PASS remains frozen from earlier evidence.
- Share extension delivery to Add panel: user confirmed on 0806, same staged UI retained in 0809. Parsing/actual save still requires device evidence.
- Referral dual-account E2E deferred to internal beta; no code consumption in this smoke.

## Current user checkpoint (read-only UI actions)
1. Map pan/pinch, open existing restaurant detail, return and check viewport.
2. Discovery load/error state.
3. Hybrid Profile > Settings: invitation entry absent.
Status: USER ACTION REQUIRED, not PASS.

## Following checkpoints
- Add/search/nearby and external share preview; save only an explicitly identified disposable test record.
- Visit create/edit, Photos/camera permissions and persistence; clean up only smoke-created records.
- Background/foreground and offline/reconnect: original records remain readable; restored connection completes sync.
- Visual/page hierarchy and Map gesture acceptance by Lafayette.
- Core account smoke must not substitute Sandbox Apple account for Taste Map identity. A second-account referral scenario stays deferred; no fabricated two-account PASS.

## Release sequence
After device checks and visual acceptance: final route cutover, clean formal Release build, signed Archive, purity/resource/extension identity, full regression, Final RC, then TestFlight upload. Production account-data continuity is a separate unresolved release concern; Private recovery must not be presented as a Production data migration. No cutover or upload while this file contains outstanding device gates.

## User results and 0810 correction
Lafayette confirmed 0809 Map drag/pinch/detail/back normal and no invitation entry.
Discovery failed: default recommendations empty despite Map20; filter Apply appeared
inert; owner activity absent from Latest. Latest source excludes self and local owner
visits are private; no visibility or stored data changes are part of this fix.

0810 restored default For You to the canonical snapshot, preserving isolated
server-side explicit queries. Shared filter validation now allows unresolved default
city and puts errors beside sticky Apply. Current-city default uses an optional
reverse-geocoded location DTO, owner-bound Native recent-city context and a guarded
React initializer; manual selection defeats late location completion.

Validation: 78 focused tests, full typecheck/formal Release-assets stage, real React
browser tests for blank-city Apply, visible distance validation, reset/explicit city,
and manual city vs late location all pass. Main/extension identity, 26 public resource
byte checks, 59 artifact-file secret scans pass. No Offer consumption.

Source/artifact/device: Taste Map Private / DebugPrivatePreview / 2026090810;
fingerprint 9395328f0c8f50166e1a3901328ead405a9fb49f9e6ddf8232a42e029cc7ec91.
Installed and launched 2026-09-08 19:31:29 +0800 on the same iPhone17ProMax.
Actual device diagnostic reports HYBRID_DEVELOPMENT with matching fingerprint;
entitlement refresh_verified. API/persistence/credential environment retains0809.
Discovery current-city, visible recommendations and Apply still require user device
confirmation. Core smoke and Final Cutover remain OPEN WORK / not accepted.

Design System Compliance: existing Discovery canonical scaffold, shared Core filter
panel, modal and sticky action bar retained. Food/Dining cards/images unchanged.
Shared Hybrid route serves Browser/Capacitor; legacy Browser Community and Native
rollback retain their existing filter UI and have no identical blank-city Apply guard.
No default-SwiftUI redesign, duplicate page or renderer promotion. Runtime visual
acceptance of0810 remains pending.

## 0813 user-confirmed device results (2026-09-08)

Lafayette confirmed ordinary launch returns to Map (“好了 正常了”). Latest now
shows10 entries and author avatar matches the profile (“10 条，一致”). These are
real-device user confirmations on0813, not inferred from unit tests. Latest count
matches the read-only audit of10 qualified Hangzhou Visits. Earlier stale/self-
exclusion findings above are historical; profile-scope linkage was subsequently
authorized and implemented in0811.

PASS: Map startup, previously confirmed Map gestures/detail/back, Referral entry
absent, Latest10 entries, matching profile avatar.
Pending: For You visible results, default current city, filter Apply/clear on device;
remaining core smoke and final visual acceptance. No final cutover/upload approval
is inferred from these individual passes.

## 2026-09-08 20:26 device evidence and D1 quota blocker

User screenshots: default For You renders cached cards, Hangzhou selected; applying
9+ displays active filters (also unvisited) but results fail. This is NOT a valid
empty result or successful live Discovery acceptance. Current-city label is visible;
actual geographic accuracy is not independently confirmed. Provider category
MKPOICategoryRestaurant leaks into card subtitle; correction remains outstanding.

Read-only reproduction with existing Development owner and current server query
failed in readDiscoveryVisitAggregates. Cloudflare API returned code7500: account
has exceeded D1 free-tier daily row-read limit. Reset stated as midnight UTC
(08:00 Asia/Shanghai). No account token was extracted or client auth fabricated;
quota-counter writes were skipped in the local diagnostic adapter, only SELECT/
WITH statements executed remotely. Failed query/error remain private.

Paused further remote probes. No billing/plan change, key replacement, data reset,
production deployment or new device installation performed. Live For You/filter
Gate remains blocked pending D1 quota restoration. Earlier observed10 Latest and
matching avatar PASS remain historical accepted results, not proof of current
backend availability.
