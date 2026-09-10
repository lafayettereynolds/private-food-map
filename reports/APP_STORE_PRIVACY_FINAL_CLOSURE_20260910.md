# App Store 1.0 privacy closure — website published, ASC delivery blocked

2026-09-10 Asia/Shanghai. This report supersedes the publication blockers in
`APP_STORE_PRIVACY_SUPPORT_CLOSURE_20260910.md`; it does not reinterpret historical tests as new runtime tests.

## Production evidence and scope

Fresh control-plane read at 2026-09-10T06:58:02.515Z confirmed Production
`eaed4e92-1881-444a-9729-1230b2882b8e`, retention=true, module SHA-256
`169b8d472573fef0e864ec5c46d83399556592515d64d2fdc08c8147a26599ae`.
The module matches the previously verified retention deployment. No API Worker,
D1/R2, cron, routes, auth, recommendation, purchase or device changes this turn.
No Final RC, iOS build, screenshot metadata edit, or Submit for Review.

Production observability remains logs enabled, persisted, invocation logs enabled,
head sampling 1, query-string redaction false; traces disabled. Search parameters
therefore cannot be classified as uncollected merely because there is no dedicated
search-history table. No credential, cookie or actual user search was extracted.

## Actual implementation evidence

- `worker/authV1.ts:181`: Apple subject mapping; stored email/relay email; new-account
  display name and stable Taste Map ID. Email is not assumed absent.
- `worker/socialV1.ts:112` and `worker/index.ts:1011`: authenticated user search q.
  Server logs retain request metadata beyond real-time handling.
- `worker/index.ts:2438`, recommendation preferences and sync models: saved explicit
  interactions/preferences, not an invented advertising analytics SDK.
- Server `follows`, `friendships`, `user_blocks`, companion/source relations form a
  social graph. It is not iOS address-book access.
- Restaurant/Visit saved coordinates and city, profile city, ratings/comments,
  photos, dishes, lists and WantToGo are linked to their account by real schema and
  owner-scoped synchronization. Precise saved places are not continuous GPS traces.
- `WorldwideRestaurantSearchService.swift`: Open-Meteo city geocoding and Photon
  restaurant search/selected-city area. Formal app initialization uses this service;
  these are not merely unused packages. Requests do not attach Taste Map credentials.
- Apple provides authentication, purchases/server notifications and MapKit.
  Cloudflare provides Workers/D1/R2 and logs. QQ Mail receives voluntary support
  correspondence. No unrelated vendor added.
- `DiscoveryAPIClient.swift:85`: systemUptime measures an in-app request interval;
  the elapsed value, not system boot time, is passed to local acceptance logging.
  This is required-reason API evidence, not evidence of automatic uploaded crashes.
- `CommunitySafetyViews.swift`, `CommunityInteractionViews.swift` and
  `Features/Profile/SocialViews.swift`: real report/block actions. No unpublished
  UGC improvement is represented as already integrated.

## Retention wording correction

30/90/365 preserved; no retention code changed. `privacyRetentionV1.ts` and
`privacyRetentionSafety.ts` were read again. The former draft wrongly generalized
90-day report/recommendation cleanup: those queries additionally require closed
accounts. The final page distinguishes that from revoked session/challenge/token/
rate-limit expiry. Commerce requires closed-account age and transaction end,
update/verification age plus dependency/active-subscription protections. Required
sync identifiers, pending investigations and incomplete deletion dependencies
are not presented as automatically purged at a blanket 365-day deadline.
Cloudflare Workers Paid log retention (up to 7 days) is explicitly separate from
D1 business retention. No claim of a new legal case-management system was added.

## Website deployed and verified

Website Worker: `fancy-fog-1341`.
New version: `a28f3e1d-1eb0-4b6c-a540-8f48f06b412b`.
Deployment: `f62df89d-3646-4adf-86ac-fcccf1e152d5`.
Deployed at `2026-09-10T07:06:46.280852Z` (15:06:46 Beijing).
Verified at `2026-09-10T07:08:52.105Z` (15:08:52 Beijing).
Previous website rollback reference: `f9d342db-afb5-4153-9085-8385dd725f01`.

Only two changed assets uploaded; index/styles/redirect configuration retained.

| URL | HTTPS status | SHA-256 |
|---|---|---|
| https://tastemap.cn/privacy.html | 200 text/html | `668262eeaecadc6a2af0881d4f87bfe4861722b1b54b5c7bedc8f1375b760d10` |
| https://tastemap.cn/support.html | 200 text/html | `bf149b12b92f24d960547d31117a5b2ef47bc1ab40a260100338fdf0bb88061a` |
| https://tastemap.cn/index.html | 200 unchanged | `bc3295a980ae60254bf88945b8ce1f146b6262281239bbe7e1c592bf719eceb1` |
| https://tastemap.cn/styles.css | 200 unchanged | `80bbae36800395f06ea3776ed5d5d353f39079907335aefc4c8beb69130c7640` |

Both legal/support pages match canonical source bytes exactly, contain the
confirmed email 418378071@qq.com, accurately label 浙ICP备2026070007号-1A as
**App 备案号**, and have zero TODO/placeholder/pre-launch copy/HTML comments.
The user has explicitly confirmed mailbox receipt; no test mail sent this turn.
Read the full rendered local pages at phone width, 16px body text, no horizontal
overflow; online identical byte hashes establish the deployed content identity.
Core UI: existing shared public CSS unchanged. Food visuals: N/A. Canonical page:
existing legal/support template retained. No duplicate app components or SwiftUI
regression introduced. No claim of a new app-wide visual acceptance.

Private evidence: `.private/privacy-final-20260910/before.json`, `after.json` and
downloaded page copies; Git ignored. No user data or credentials in this report.

## App Privacy final values (NOT YET SAVED IN ASC)

F = App Functionality, P = Product Personalization. Every collected row is linked
YES and tracking NO. Linked is conservative where authenticated request metadata
has not been demonstrably deidentified before collection. This does not claim
every diagnostic record contains a literal userID. No Analytics/Advertising/
Other Purposes selected without corresponding actual use.

| Data type | Collected | Linked | Tracking | Purpose | Own-app manifest |
|---|---|---|---|---|---|
| Name | YES | YES | NO | F | MATCH |
| Email Address | YES | YES | NO | F | MATCH |
| Contacts / social graph | YES | YES | NO | F, P | MATCH |
| Precise Location | YES | YES | NO | F, P | MATCH |
| Coarse Location | YES | YES | NO | F, P | MATCH |
| Photos or Videos | YES | YES | NO | F | MATCH (photos; no invented video capture) |
| Other User Content | YES | YES | NO | F, P | MATCH |
| Customer Support | YES when used | YES | NO | F | N/A: external mail correspondence, not a new app upload pipeline |
| Search History | YES | YES | NO | F | MATCH — added |
| User ID | YES | YES | NO | F, P | MATCH |
| Purchase History | YES | YES | NO | F | MATCH — removed unsupported P |
| Product Interaction | YES | YES | NO | F, P | MATCH |
| Performance Data | YES | YES | NO | F | MATCH — retained server timing diagnostics |
| Other Diagnostic Data | YES | YES | NO | F | MATCH — retained request/errors |
| Other User Contact Info | NO separate collection established | N/A | NO | N/A | N/A |
| Other Usage Data | NO separate collection established | N/A | NO | N/A | N/A |
| Crash Data | NO app-upload pipeline established | N/A | NO | N/A | N/A |

Apple's Contacts definition explicitly includes social graph. No Contacts OS
permission is implied. Optional support disclosure exemption was not assumed:
all of Apple's conditions have not been proved for external email. Purchase
history remains F, not restaurant-recommendation personalization. Saved search
parameters have a technical/security purpose, not proven recommendation training.

ASC action status: **NO changes saved/published**. The prior observed seven-type
published label is historical, not a fresh verified current state. User completed
Chrome login, but its native automation returned only a window title and no
accessible content or screenshot even after foreground/reconnect. The separate
in-app Apple login tab then timed out on reload and reattachment. Do not call this
an Apple account permission failure or pretend a blind save succeeded.
The accurate diff is ready; live ASC read, save/publish and readback remain required.

## Manifest and permissions

Main manifest source now has 13 collected types; SearchHistory, PerformanceData,
OtherDiagnosticData added, PurchaseHistory purpose corrected to F only. Support
email is not mechanically copied into the Share Extension or SDK manifests.
Their existing empty collection declarations remain unchanged.

Required-reason APIs:
- FileTimestamp C617.1: app-managed backup/poster temporary-file timestamps.
- UserDefaults CA92.1: app-owned preferences.
- SystemBootTime 35F9.1: in-app Discovery elapsed request measurement — added.

`scripts/audit-ios-privacy.py` retains strict archive/source equality, known SDK
inventory, duplicate and exact-purpose checks. It now checks the reviewed new
inventory instead of requiring the old inaccurate declaration. No archive was
patched or manufactured. An old 1012 archive is not expected to match this source.

Info.plist/project permission configuration unchanged: WhenInUse location,
Camera, PhotoLibraryAdd; system picker for chosen images. No Contacts, Microphone,
Bluetooth, Always/Background Location permission added.

Tests: `python3 scripts/test-privacy-submission.py` 5/5 PASS, including six
negative manifest variants; plist parsing and `git diff --check` PASS. Official
website Wrangler dry-run PASS; deployment and HTTPS hash verification PASS.
No full native build/suite run is claimed for this source/metadata-only change.

## Consistency and remaining delivery gates

| Comparison | Result |
|---|---|
| Production ↔ published Privacy Policy | MATCH |
| Actual support workflow ↔ published Support | MATCH |
| Production/app source ↔ proposed App Privacy values | MATCH |
| Production/app source ↔ updated main Manifest source | MATCH |
| OS permissions ↔ policy / actual capability use | MATCH |
| Current published ASC ↔ final values | UNVERIFIED — update/readback blocked |
| Current signed 1012 ↔ new Manifest | MISMATCH — expected; include in unified new RC |

Known unresolved **delivery gates: 2**, not a claim of zero actual submission
mismatches. Declaration/source work is ready; ASC remains blocked, and signed
artifact parity belongs to the future unified RC explicitly prohibited this turn.
New iOS build required: YES, but do not generate a standalone privacy build.
Combine this patch with approved UGC commit
`f1360004127131c07c8be337a0c1c8238849a6f9` in the separately authorized RC workflow.

RETENTION: PASS
PRIVACY POLICY / SUPPORT PAGE: READY
PRIVACY POLICY DEPLOY / SUPPORT PAGE DEPLOY: PASS
PLACEHOLDERS ONLINE: 0
SUPPORT EMAIL VERIFIED: YES
APP PRIVACY UPDATED: NO
APP PRIVACY: BLOCKED (delivery, not an excuse to under-declare)
PRIVACY MANIFEST CHANGED: YES
PRIVACY MANIFEST: READY (source; signed RC pending)
INFO.PLIST: READY
CONTACTS PERMISSION: NOT ADDED
NEW IOS BUILD REQUIRED: YES
SUBMISSION PRIVACY: BLOCKED
NEXT BLOCKER: accessible ASC session for save/publish/readback; then unified RC artifact validation.

## Primary definitions consulted

- https://developer.apple.com/app-store/app-privacy-details/ — collection beyond
  real-time request, social graph, optional-disclosure conditions, categories/purposes.
- https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests
  — own-app/SDK manifest scope; not mechanically identical to Nutrition Label.
- https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype
  — systemUptime and approved elapsed-time reason 35F9.1.
- https://developers.cloudflare.com/workers/observability/logs/workers-logs/
  — invocation logs and Paid retention.

Previously identified Open-Meteo commercial-use/license verification is a separate
provider-terms question, not resolved by changing a privacy declaration. No plan
purchase or provider migration was attempted, and no legal compliance guarantee
is implied by this factual disclosure audit.
