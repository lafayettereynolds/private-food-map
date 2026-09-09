# Taste Map Hybrid Migration Status

Updated: 2026-09-06
Bridge: `TasteMapNative.v1`
Production default: `NATIVE_PRIMARY` (current SwiftUI application)

## Status definitions

2026-09-08 Premium entry presentation retains the calling React route and its
mounted sheets/forms using PremiumReturnLayer. Back closes only that child layer;
it does not mutate Native/browser route history or return to a hard-coded root.
Direct Premium deep links retain the existing standalone route. Route ownership
and production-primary status are unchanged.

2026-09-07 Premium Gift adds authority-backed source/text/manage-capability DTOs
and a separate internal Worker Admin page. Premium route ownership is unchanged.
Local regression and installed Hybrid/Native evidence are recorded in
`docs/PREMIUM_GIFT_ADMIN.md`; this does not imply a Worker deployment, physical-device
installation or production-primary switch.

| Status | Meaning |
| --- | --- |
| `NATIVE_PRIMARY` | Current SwiftUI/native route owns production behavior |
| `HYBRID_POC` | Isolated feasibility evidence only |
| `HYBRID_READY` | Shared React route, adapter, native DTO/service, tests and local shell are ready; no production switch |
| `HYBRID_INTEGRATED` | The route is connected to the formal Taste Map target, real native auth/data, typed ownership/handoff and persistent runtime; Release is still native-primary |
| `HYBRID_PRIMARY` | Explicitly approved production owner |
| `NATIVE_ROLLBACK` | Native route retained as tested rollback after a production switch |
| `RETIRED_AFTER_MIGRATION` | Native route may be removed only after separate approval and stability window |

## Route matrix

| Surface | Status | Phase 1 evidence | Production owner | Next gate |
| --- | --- | --- | --- | --- |
| My Map / My List | `HYBRID_INTEGRATED` — Native MapKit surface | Shared `MyMapBrowsePage` owns the page chrome/state; Browser keeps the Web provider while iOS uses the persistent established `RestaurantMapView`/`MKMapView` through typed `map.surface.update`, viewport and selection events. Owner-scoped `map.viewport`, Native location/avatar, owner-photo/category visual policy and deterministic markers remain authoritative. Fixed-Simulator pan, pinch, selection, detail/back and Map/List restoration have functional evidence; no separately verified Map Gesture Smoothness commit exists in the integration inventory. | SwiftUI / Native MapKit | **Map Gesture Smoothness Gate OPEN**, then Lafayette Product Acceptance, real-iPhone smoke and explicit `HYBRID_PRIMARY` approval. AMap Web credentials and merchant-photo credentials are not iOS gates. |
| Discovery / Community | `HYBRID_INTEGRATED` | One shared five-tab React UI, shared Activity Card/FilterBar, Visit-rating semantics, explicit Activity/Visit/author/Restaurant identity, authoritative Like/Comment and WantToGo mutations, exactly three Restaurant actions (Record Visit / WantToGo / Roulette), Hybrid-owned Visit/Roulette routes, preserved return state, owner-safe adapters, exact/negative Product contracts, batched permission-safe `RestaurantUGCImagePool`, activity/public/category visual matrix and uploader ≠ recommender/trend-source contracts | SwiftUI | Lafayette visual review, real-device interaction smoke and explicit `HYBRID_PRIMARY` approval |
| Add Restaurant / Nearby | `HYBRID_INTEGRATED` | Browser and Capacitor compose one shared React Search/City/Nearby/Share/Manual acquisition UI; typed MKLocalSearch provider, fresh GPS, distance, dedupe, owner/public/category resolution, shared Search/Nearby resolver and Share Extension bridge; candidate selection enters canonical Restaurant Detail and has no merchant-photo dependency. Fixed iPhone 17 Pro Simulator input-focus evidence covers `16px` controls, keyboard operation, unchanged viewport scale and four reachable capabilities. | SwiftUI | Real-iPhone Location/provider/Share smoke, Lafayette Product Acceptance and explicit `HYBRID_PRIMARY` approval |
| Profile / My | `HYBRID_INTEGRATED` | Shared `ProfilePage`, real AuthSessionManager/current-user DTO, formal signed local bundle, native/Hybrid handoff and Debug fixed-Simulator evidence | SwiftUI | Lafayette Product Acceptance, real-device smoke, performance acceptance and explicit `HYBRID_PRIMARY` approval |
| Restaurant Detail | `HYBRID_INTEGRATED` | Canonical React detail, stable Restaurant ID/DTO/image descriptor, formal route ownership, Native → Hybrid and Hybrid back regression; real MapKit name/address/coordinate/phone/website/category survive candidate → SwiftData → sync/backup → Hybrid projection, while unavailable hours/images/ratings/prices remain explicit no-data values | SwiftUI | Cross-entry Product Acceptance, real-device Provider smoke and explicit `HYBRID_PRIMARY` approval |
| Visit editor | `HYBRID_INTEGRATED` | One shared React editor; typed Visit/Dish/photo draft DTOs; owner-scoped `LocalVisitRecordingStore`; existing mutation queue; native PhotosUI picker and `PhotoTransferCoordinator`; edit/create/delete handoff and automatic detail refresh; formal Release purity scan | SwiftUI | Lafayette Product Acceptance, real-device photo/camera-library smoke and explicit `HYBRID_PRIMARY` approval |
| Lists / Public Lists | `HYBRID_INTEGRATED` | Shared React list renderer, canonical Restaurant navigation and existing Native list-manage handoff | SwiftUI | Lafayette visual review, mutation smoke and explicit `HYBRID_PRIMARY` approval |
| Roulette | `HYBRID_INTEGRATED` | Shared approved wheel, current candidates and canonical Restaurant transition | SwiftUI | Lafayette visual review and explicit `HYBRID_PRIMARY` approval |
| Analytics / Posters | `HYBRID_INTEGRATED` | Shared five-mode infographic family, five real 9:16 poster renderers and typed system share | SwiftUI | Lafayette visual review, real-device share smoke and explicit `HYBRID_PRIMARY` approval |
| Premium / Paywall | `HYBRID_INTEGRATED` | Shared paywall; typed StoreKit product/purchase/restore/manage bridge; server-backed entitlement state remains authoritative | SwiftUI/StoreKit | Real App Store Connect Product IDs, Sandbox/TestFlight verification and explicit `HYBRID_PRIMARY` approval |
| Settings / Data / Backup | `HYBRID_INTEGRATED` | Shared Settings IA; real Sync status/run; live permission status; typed Backup/Import and Account Delete native routes; no fake legal/product/account state | SwiftUI | Real-device settings smoke, legal/external Release gates and explicit `HYBRID_PRIMARY` approval |

## Batch 2 completion boundary

Phase 2A embeds the signed local Capacitor/React runtime in the formal Taste Map target and connects Profile and Restaurant Detail to existing native auth, owner-scoped data, typed navigation, deep-link/share/lifecycle event contracts and a persistent WebView. Phase 2B adds My Map / My List. Batch 1 integrates the remaining Product UI through shared React components and exact Product/negative contracts. Batch 2 closes the typed Native capability boundary for Visit/Dish writes, photo library and camera capture, local originals/upload retry/delete, fresh-GPS Restaurant acquisition, Share Extension ingestion, StoreKit, Sync, permissions, Backup/Import, Account Delete entry and system actions.

Every integrated route still has production owner SwiftUI. Debug internal acceptance can opt into `HYBRID_DEVELOPMENT`; Release contains no such runtime mode or launch switch and continues to open the current SwiftUI application. Existing SwiftData, mutation queue, SyncEngine, Auth/Keychain, PhotoTransferCoordinator, StoreKit entitlement, Backup/Import and Account Delete services remain authoritative. Current SwiftUI surfaces remain intact as rollback. No Bundle ID, Team, SwiftData schema, Worker, D1, R2, real StoreKit product configuration or Production state changed.

The 2026-09-06 Profile editor exit correction removes duplicate Back + Cancel from Profile/Settings editor variants and prevents the Native host from adding a second navigation toolbar to self-navigating destinations. Shared Native/React icon controls preserve draft disposal, Save and pending-save dismissal locks. It does not change this ownership matrix or the production default. Regression evidence and remaining real-iPhone boundary are recorded in `reports/profile-editor-single-exit-2026-09-06/REVIEW.md`.

The 2026-09-06 Visit save/back correction preserves the same route ownership. A restored editor previously replaced only its Web URL while Native appended Detail above the old editor; delayed Back then reopened that editor. Optional typed replacement now completes both histories, and Back reconciliation waits for the local traversal before applying its latest Native result. Source/browser transport regressions are intermediate evidence only; the new Native coordinator tests and eventual staged/installed verification must be recorded by the integration run. No device was operated or bundle staged for this scoped correction.

The My Map route's integrated shell/DTO status does not by itself constitute
real-map interaction acceptance. An offline/fallback screenshot cannot satisfy
pan, pinch, center, zoom or bounds gates. The persistent Native MapKit surface
has functional fixed-Simulator evidence, but Map Gesture Smoothness remains OPEN
until a separately verified smoothness fix and sustained-gesture acceptance exist.
Real-iPhone pan, pinch, viewport and performance smoke also remains required before
any primary-route switch. No AMap map, AMap merchant-photo API, AMap credential,
or external merchant-photo gate is part of this closure.

The 2026-09-05 marker correction preserves these route states and map engines.
Browser and Native MapKit share fixed circle anchors, natural city/street
overlap, wider-area Restaurant-image representatives and exact-coordinate
stacks with real member lists. No marker shows quantity numbers or numeric badges.
Native's annotation/hit frame remains `44 × 44pt`; only its centered unselected
visited inner circle scales within 24–28 points, yielding a 28–32-point visible outer
circle including the unchanged 2-point white ring. Native selection adds 2–4
points to the inner diameter. Browser uses shared 32 px overall / 36 px selected
tokens on mobile and desktop, without continuous diameter scaling. Shadows are
weaker. City and street views (`≤0.8°` latitude span) retain every distinct
Restaurant coordinate as a naturally overlapping image marker. Only strict
coordinate equality permits a stack/list; the previous 50 m proximity rule is
superseded. Wider-area grouping begins above `0.8°` and reaches its full collision
radius at `2.4°`, retaining the highest-priority member's own image and coordinate,
not a number. Tap zooms toward members; exact-coordinate stacks open the complete
real Restaurant list with `此处` wording. Original member coordinates and totals remain
authoritative; no mall identity or administrative boundary is fabricated.
Free-slot displacement and circle bottom anchoring are superseded. Acceptance
must verify actual-circle projection error and diameter, individual city markers,
reversible wider-area grouping, absence of marker numbers and exact-location
member access, not merely root-frame dimensions or
unchanged stored coordinates; this contract update does not close the existing
gesture, visual-review or real-device gates.

Exact-coordinate stack acceptance additionally requires real member imagery:
the highest-priority front Restaurant and up to two actual member-image/fallback
layers behind it, never empty outline plates or copied leader images. The front
circle remains the geographic anchor; fixed back offsets `(-10, -8)` and `(8, -10)`
exist only inside this same-coordinate composite. Complete membership remains in
the real list. This requirement alone does not establish runtime acceptance.

## Restaurant Visual Closure

### Overnight 2026-09-05/06 scoped correction (no route-status promotion)

The near/regional marker dimensions documented above apply through `2.4°`;
beyond that, the continuous far-scale override reaches Native 14-point outer
diameter / Browser 14 px CSS border-box at `80°`, without resizing the 44-point
anchor. The rejected fixed nearby five-image flower arrangement is removed.
Visited/want/recommended now retain separate query/filter banks while sharing
the same map instance and same-scope Map/List state. Owner Profile statistics
use compact shared 8 / 4 / 44 / 10 spacing/hit-target tokens.

Acquisition adds shorthand/completion supplementation, accepted same-city GPS
refresh after expiry, a 500 m Nearby POI supplement, and typed continuation.
Reduced accuracy is actionable failure, not successful precise Nearby. Opaque
Native continuation and async results are owner/query/generation scoped.
The scoped installed-QA gate passed: 154 TS tests, 80 Native tests, five UI tests,
and current stage/built/installed resources plus Release purity verification.
Evidence is in `reports/night-review-2026-09-05/REVIEW.md`. This does not establish
that an actual iPhone at the reported Hangzhou shop receives that exact provider
listing. The morning real-device and city-density visual approval gates remain
open. No primary route or production deployment was changed.

The later 2026-09-05 pending-marker emphasis preserves every route state:
`想吃 / 推荐` add 4 points to diameter; visited stays unchanged. Native normal
pending outer circles are 32–36 points, selected at most 40, within the fixed
44-point root. Browser pending CSS sizes are 36/40 px vs visited 32/36 px, with
one fixed 44 px anchor. GPS distance no longer reduces pending emphasis.
Deterministic Native overlap is supplied through MapKit `zPriority` rather
than competing root CALayer ordering. This scoped correction requires fixed-QA
pan/member-identity and sizing evidence and does not close real-device or
general map gesture-smoothness gates.

The current visual contract is integrated for Map, Add Search/Nearby, Restaurant
Detail and all five Discovery tabs. Browser and Capacitor consume the same React
descriptor renderer; Native MapKit consumes the same category IDs and owner-only
Map policy. Worker social feeds batch-load eligible UGC and preserve Photo/Visit/
Profile visibility, block, deletion and moderation boundaries. Other-user public
UGC is not exportable by default. This is Final Visual Closure work only and does
not start Hybrid Primary or Batch 3.

## Discovery data-chain stage 1 (2026-09-06; no route promotion)

The additive `discovery.page` v1 DTO, optional capability, Native/Browser adapter
boundary, dispatcher and authenticated Native page producer are implemented.
An independent session-only coordinator binds owner, mode, requested/resolved
city, 7/30-day trend window, cursor and snapshot; it rejects late/cross-scope
results, merges genuine continuations, preserves the same query on retryable
failure, and clears affected-mode pages on 401/403. Existing `content.snapshot`
and its structured per-mode refresh-error chain remain independent and unchanged.

Evidence for this stage: the local Swift bridge suite passes 38 tests, including
12 dedicated query/continuation/envelope regressions; the TS adapter/platform/
product selection passes 74 tests; app TypeScript check and Swift syntax parse
pass. Two iOS URLSession → projection → coordinator → bridge integration tests
are added for actual URL parameters, >20 results, capacity errors and absence of
legacy cache writes; they still require execution in the canonical iOS test
runner. No worker deployment, DB migration, resource staging or app installation
was performed for this stage.

Not complete: shared UI city/mode/window requests and load-more controls; Shell
canonical recommendation refresh/scope reconciliation; Native page-target and
image authorization; real engagement hydration (new page results explicitly
disable interactions and mark counts unknown); Browser authenticated page/social
production (capability deliberately false); following/latest community pagination;
and runtime/real-device/Release acceptance. Existing first-page content consumers
therefore still do not provide a complete selected-city paginated result. These
remaining gaps must not be marked closed by the worker aggregate fix or by the
existence of this interface. Trending's approved removal of the recent-trend tag
and the entire community-rating group remains unchanged.

### Selected-city presentation continuation (2026-09-07)

The new separately negotiated `discovery.cityPage` connects the shared five-tab
city-search UI to a session-only Native query and authorization overlay. Explicit
city selection never writes global SwiftData placements or changes Map's default
For You snapshot. Accepted targets support existing Detail/Restaurant actions,
descriptor-authorized photos and current-owner recommendation exclusions.
Following/Latest use actual response engagement; three Discovery modes still
honestly declare unknown social counts, with no fabricated Like/Comment numbers.

Native verification: 19 tests in DiscoveryPageIntegrationTests,
CommunityCityAPIClientTests and P3CDiscoveryTests passed, covering complete pages,
owner/city/cursor/late isolation, detail and preference authorization, no legacy
cache writes, and the explicit five-mode QA producer. Log:
`/tmp/tastemap-city-session-final-tests.log`. DEBUG Visual QA has an independent,
clearly labelled mock city dataset (36 items, 20+16 pages), not real city evidence.
Formal staging/installed Simulator inspection remains the parent's gate.

Still open: production Community city API deployment is held; Browser has no
authenticated city/social producer; authoritative Discovery social count reads
remain unavailable; real-service/physical-device acceptance is not claimed.
No production route owner or Worker deployment changes in this source slice.

## Analytics identity/report stage (2026-09-06; integration verification pending)

Integrated local evidence (2026-09-06): 167 JS tests in 11 suites passed, the
real-component Browser probe passed readable data / history / person selection /
PNG share checks, and 21 Native tests in 4 suites passed in
`/tmp/tastemap-analytics-chest-acceptance-20260906.xcresult` (including the 3 new
Analytics identity cases). Formal staged and built-app resources matched 18 files
byte-for-byte. This is NOT physical-device Analytics acceptance or sync.
**Release hold:** Lafayette subsequently paused the treasure-chest design. The
current local bundle includes that candidate and must NOT be synced or released
as approved; isolate/exclude it before any unrelated future sync.

The subsequent source-only isolation defaults both shared Web and Native marker
shape gates to off and restores the existing circle/dashed formal renderers,
including real same-coordinate back members. Candidate PNG/renderer code remains
preserved and independently testable, not approved for activation. Five focused
JS suites (51 tests) and Swift syntax parsing pass; staging, rebuilt-asset identity
and installed-device proof belong to the next integration run. No route status,
map geometry or device installation changed during this isolation.

The shared Analytics companion/source report now consumes an additive, explicitly owner-proved `profile.analyticsIdentity` bundle. Native projects only real current-owner directories and existing Visit source associations through read-only local model access; Browser projects its actual companion directory. Stable IDs, ambiguous legacy names, tombstones, source attribution, sample thresholds, selected-entity evidence and share-privacy tags are covered by model/projection regressions. Missing identity information remains unavailable rather than being reconstructed from names or linked social-user IDs. Old profile DTOs remain decodable without this optional field.

This stage does not close Browser's missing formal recommendation-source directory/Visit-link channel. Native rollback analyzers remain separate consumers and are not retired by the new shared report. Native identity integration now passed the canonical iOS test runner as recorded above, but this does not claim simulator visual or real-device Analytics acceptance. Existing route statuses remain unchanged.

## Required update rule

The 2026-09-06 food-list first stage adds typed owner-scoped detail reads, permission-checked public pagination, retained original coordinates, explicitly sourced nullable ratings and real public-share link generation to the existing shared detail. This is an intermediate source/runtime-browser boundary, not complete List acceptance: food-list Map/List switching and return-context integration, legacy Browser create/edit handoff, Native rollback parity and formal installed-artifact verification remain open. No MapKit route gate or production route owner changes in this stage.

The 2026-09-06 Discovery correction adds shared content-sized reason tags, bare social icons/counts and explicit match/probability display modes without promoting a route. `calibratedLikeProbability` is an optional backward-compatible DTO/cache channel only; no production calibrated model or approved liking-target producer exists. Current heuristic percentages are displayed as `口味匹配度`. Browser CSS and shared-component regression are intermediate evidence; formal staged/built/installed checks remain required for the integrated app.

Any commit that changes a surface's status must update this matrix and include the evidence that justifies the transition. Neither `HYBRID_READY` nor `HYBRID_INTEGRATED` may be promoted to `HYBRID_PRIMARY` without Lafayette's explicit approval. `NATIVE_ROLLBACK` or `RETIRED_AFTER_MIGRATION` cannot be inferred automatically.


## Referral Reward acceptance checkpoint — 2026-09-07

Private-directory addition (2026-09-08): Settings gains `settings/directory` using one shared React page and a typed authenticated Native boundary; current production Settings remains NATIVE_PRIMARY. Native Settings also exposes the management entry. Local implementation is not a readiness promotion: remote migration/deployment and authenticated cross-account populated-state acceptance remain pending. See `PRIVATE_DIRECTORY_SETTINGS.md` for scope and evidence.

- Route ownership is unchanged: NATIVE_PRIMARY production root, shared React detail at `settings/referrals` for Hybrid/Browser. No new bottom tab.
- Local server tests cover real registration + sync qualification, atomic awards/audits, max-five concurrency/idempotency, Gift/Apple/Lifetime handling, revoke compaction and owner isolation.
- Formal local bundle was staged and byte-verified against both Debug and Release Simulator apps. Native and React Hybrid installed-runtime tests exercise the invitation dashboard, return path and real system Share Sheet. Browser formal preview verifies explicit no-session/error/retry rendering.
- Release purity scan excludes referral QA fixtures along with existing Debug/Premium bypass markers. No release override was introduced.
- Production activation remains pending: migration 0035, Worker/cron deployment, authoritative Apple notifications/configuration, confirmed production API/link domain, signed Associated Domains and real-device Universal Link/Apple registration acceptance. No remote migration/deployment or real reward grant was executed.
- See `docs/REFERRAL_PREMIUM_REWARD.md` for the exact implementation/test inventory and limitations. This checkpoint does not promote any route to HYBRID_PRIMARY or claim production launch readiness.


## 2026-09-08 — First TestFlight Referral visibility hold
Lafayette defers the real two-account Referral E2E to internal beta follow-up. The first TestFlight hides Settings invitation entry and rejects direct invitation routes/registration preparation in Browser, Hybrid and Native rollback. Reuse the existing signed ProductionEnvironment.json product configuration, referralAvailable=false, without Debug/URL/local-storage overrides. Worker independently blocks invitation landing/dashboard and new-registration referral attribution; existing entitlements, qualification/settlement implementation, admin permissions, Offer mappings and inventory remain retained. No unverified invitation allocation or code consumption. This is release product visibility, not a new remote flag platform; reopening requires a reviewed config/build/deploy after real E2E PASS.
Core UI Settings rows and existing unavailable state remain canonical; Food/Dining visuals and page templates are unchanged. Do Not Regress: all entry paths, native bridge, stale saved invite code and server attribution must remain closed together. Normal StoreKit evidence remains PASS. Referral E2E is non-blocking only while this closure is effective. Real core smoke and visual/map approval still precede any HYBRID_PRIMARY cutover.

## 2026-09-08 — Private-device share handoff correction in progress

0805 real-device evidence confirms extension execution and App Group persistence, but Hybrid did not display the pending share. Shell now handles the existing typed shareExtension.received destination; Add expands its existing share panel when the pending fingerprint is present, including mount after an earlier event. No automatic Restaurant save, queue consumption or new platform API. Native rollback and production route ownership remain unchanged. Discovery errors now distinguish transport timeout/offline, invalid response and generic failures, with bounded content-free native diagnostics. Source regression is not device E2E PASS; a fresh Private build and actual pending-share/discovery checks remain required.


### 2026-09-08 Private device 0808 API configuration correction

`ProductionEnvironment.json` contains the release-safe Boolean Referral flag. The native production API reader now decodes only its typed `apiBaseURL` field rather than requiring all JSON values to be strings. Old parser reproduces a missing API base URL; five shipping-branch configuration cases pass after correction. 0808 source/artifact/device identity is verified with `Taste Map Private` / `DebugPrivatePreview` / HYBRID_DEVELOPMENT. Real device reaches auth but its old refresh session is rejected with 401; same-account reauthentication and successful Discovery refresh remain pending. Lafayette confirmed pending-share panel delivery on 0806. No HYBRID_PRIMARY transition or overall smoke acceptance is implied. Evidence: `reports/HYBRID_DEVICE_SHARE_AND_API_0808.md`.


### Private account recovery 0809
Private Preview now selects Development API explicitly and the credential namespace follows API environment. Its existing local persistence namespace remains unchanged to preserve pre-cutover Lafayette rows. Ordinary Release retains signed Production configuration. This is authorized account-data recovery, not HYBRID_PRIMARY or Production migration. Build 0809 device entitlement verified, original 27 restaurants/24 visits retained with zero original UUIDs missing. See `reports/ACCOUNT_IDENTITY_ENVIRONMENT_AUDIT_0808.md` for evidence and remaining gates.

### 0810 Discovery smoke correction (verification in progress)
0809 physical-device Map pan/pinch/detail/back and hidden Referral entry were
confirmed by Lafayette. Discovery default For You incorrectly bypassed the
canonical Map snapshot; filter Apply rejected an empty Profile city. Shared React
now restores canonical default recommendations, keeps explicit queries isolated,
and exposes validation beside sticky actions. Optional Native detectedCity supplies
the real current-city default across Discovery tabs without changing profile data.
Latest keeps existing visibility rules; owner private history remains in 味觉足迹.
Physical-device confirmation of this correction remains open; no primary cutover.

### 2026-09-09 Final Integration / personal-filter checkpoint

Latest source status: authorized Release HYBRID_PRIMARY cutover is implemented
for the new 2026090907 Internal candidate, with Native rollback retained. The
route registry marks the integrated shared routes HYBRID_PRIMARY; native capability
handoffs remain native. Internal Release uses Development without DEBUG/QA or
Sandbox-only purchasing UI. Source automation 1561/1561 and bridge Swift 42/42
pass; staged Web parity is 26/26. Signed artifact, fresh runtime and real-device
acceptance remain separate gates. Historical "no cutover" statements below are
prior checkpoints, not current source selection. No Production deployment or
TestFlight upload is implied.

Development continuation: missing 0040 was safely rehearsed on a private export, applied once via an isolated migration runner and verified without changing any old ledger row or checked entity/audit count. 0041/0042 were not repeated. Development Worker `581b3f08-fc17-44f6-a089-c7d720d73769` is active with bindings/settings preserved and retention still disabled; health/protected-route probes pass. This supersedes the deployment blocker below, not the outstanding cutover/archive/physical-device gates. See `reports/FINAL_INTEGRATION_DEV_DEPLOYMENT_2026-09-09.md`.

Sync-safe Photo Delete has been semantically integrated while preserving the frozen dirty baseline. Browser/Hybrid/Native For You filters now distinguish 预计喜欢度 (/10 historical owner prediction) and 口味匹配度 (%); public/community rating is no longer a filter substitute. Source tests 1558/1558, Native filter/query 16/16 and Capacitor Photo Delete/control 2/2 pass. Full Native baseline comparison has no new failures, not an all-green claim. Unsigned Release compilation, purity and 26/26 staged/built asset parity pass. No cutover, new signed RC, device install, deployment or TestFlight upload yet. Dev 0041/0042 are already applied; absent 0040 cleanup-lease columns must be reconciled before a full-source Worker deployment. See `reports/FINAL_INTEGRATION_PERSONAL_FILTER_CHECKPOINT_2026-09-09.md` for exact scope and evidence.

### 0811 linked homepage/footprint scope (verification in progress)
Lafayette authorized historical Visit and attached-photo scope to follow homepage
settings. Native persistence reconciles owned records via the normal mutation queue;
new Visit writes use current Profile scope. Browser persistence/settings use the
same semantics. No schema, account or primary-renderer migration. Latest no longer
excludes the authenticated author's otherwise-qualified public Visit. Private and
friend gates remain enforced. Nil optional companion fields emitted by Swift are
accepted as null in the server decoder, repairing a real prerequisite sync rejection.
Physical-device/public-read verification remains pending.
