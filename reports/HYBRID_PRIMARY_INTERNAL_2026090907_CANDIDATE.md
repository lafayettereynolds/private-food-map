# Internal Hybrid candidate 2026090907 — 2026-09-09

## BLOCKER / evidence correction — 21:31 Asia/Shanghai

Follow-up: the user-authorized bounded source repair and offline rehearsal are
complete; signed replacement 2026090908 is prepared but NOT installed. See
INTERNAL_STORAGE_RECOVERY_2026090908.md. This does not retroactively make the
0907 active queue pass or resolve its ten conflicts.

Interactive create exposed a store-namespace regression in the new Internal
configuration. 0907 selects TasteMapAppEnvironment.development and therefore
TasteMapDevelopment.store. The earlier snapshot script only copied TasteMap.store.
Its byte-parity and resolved-audit checks are true for that preserved old store,
but MUST NOT be interpreted as proof of the active 0907 queue being zero.
Earlier active-queue/preservation conclusions are superseded by this correction.

The active Development store and WAL/SHM were copied with the process briefly
suspended/resumed and backed up at
/tmp/tastemap-0907-install.rUANDh/active-development. Integrity PASS. Same owner
tm_Ann0z_DQyodqnbed-lFGZRed, 28 Visits. New Visit 35B0FD40CC4B431EBE9F36E189DB8224
has note 0907验收, synced/version 1; its PhotoAsset
8C0C569F00074A8399488C086E6622AB is uploaded/synced/version 1 with both original
and thumbnail storage keys present. The console also recorded upload_complete.

However, this active store contains TEN unresolved conflicted mutations
(9 Visit upserts, 1 Profile upsert), all with
server_changed_while_local_mutation_pending and no resolution. The previous
TasteMap.store still contains the seven resolved recovery audit rows. Do not
conflate the two queues or clear/auto-resolve either. Exact mutation identifiers
and errors are available in the private active-store snapshot.

The prior Private Preview endpoint override retained the existing local store;
the new TASTEMAP_INTERNAL_BUILD changes the environment used for store selection.
This is not a Photo Delete failure, and the newly created Visit/photo succeeded.
Historical provenance of the ten active conflicts and safe store reconciliation
remain to be diagnosed. Do not presume data loss, completion or conflict resolution.

REAL DEVICE SMOKE: BLOCKED. FINAL RC ACCEPTANCE: NOT PASS. TESTFLIGHT: NOT RUN.
Pause new writes/deletion tests. No direct DB writes, queue clearing, owner changes,
new build/install or automatic store migration were performed in this diagnosis.

### Read-only root cause closure

8567035 Private Preview has TASTEMAP_PRIVATE_PREVIEW without DEBUG: the storage
environment therefore remains production (legacy TasteMap.store), while the
explicit APIConfiguration branch uses Development. 0907 added
TASTEMAP_INTERNAL_BUILD to TasteMapAppEnvironment.current, unintentionally changing
local store selection along with Premium cache and SocialOutbox namespaces.
The API endpoint itself remained Development; this is not a Production cutover.

Nine Visit mutation timestamps are 2026-09-09 21:20:09 local (0907 launch), with
baseVersion 1. Runtime contentSnapshot calls synchronizeFootprintVisibility,
which enqueues historical Visits whose scope differs from the cached profile.
Their queued visibility is public; the current and old recovery records are
already public at version 2. Conflict protection prevented stale writes from
silently overwriting the newer server revision. The Profile mutation dates to
2026-09-06 15:45:55; active profile version 5 failed, recovered old profile version 6
synced. None of these ten mutation IDs exists in the recovered old audit table.

Entity comparison: all 28 old Restaurants and all 27 old Visits are present;
only the new 0907 Visit is additional. Existing Visit business columns match;
differences are lastSync and nine conflict sync-status fields. Lists/items retain
the same IDs and counts. The one old-only photo is a synced deletion tombstone
with binaryDeletedAt; the active-only photo is the new uploaded test photo.
All five Dishes and five VisitDish associations have matching remote identities;
one Dish and the associations have independently generated local IDs in the
other store, explaining corresponding local photo linkage differences. Do not
copy raw database rows between these stores.

Recommended bounded repair, NOT EXECUTED: preserve the accepted legacy local
namespace for this Internal upgrade while retaining explicit Development API
and credential configuration. Add regression tests for storage, API, cache/outbox
and Release fixture isolation. Validate on copied stores and verify the new Visit
and photo can be recovered by normal server pull before any device switch. Retain
the alternate store and all ten conflict records as evidence; do not clear or
force-resolve them. Generate a new build only after source/off-device gates pass;
perform a new backup before any separately confirmed overwrite installation.

## Identity and authoritative install artifact

- Branch: feature/hybrid-final-integration
- HEAD: 9859b8cbc99e65984c8cfd935b2ec82a4e2be2a8 plus preserved integrated workspace; HEAD alone is not the source identity.
- Build input workspace fingerprint: 1edf43e7a2cff1089552fc7393426f02f2a8791ed0adf3a1bc232e08e7b1fd21 (before this report).
- Build: 2026090907, Release + Configuration/ReleaseInternal.xcconfig.
- Renderer: HYBRID_PRIMARY; Native rollback retained.
- Bundle: com.lafayette.tastemap; Team: 7G5J9MJX88.
- API: https://api-dev.tastemap.cn; normal Premium, no Sandbox-only product UI.
- Archive: /tmp/tastemap-cutover.GEkdto/TasteMap-2026090907.xcarchive
- **Only install candidate:** /tmp/tastemap-cutover.GEkdto/TasteMap-2026090907.xcarchive/Products/Applications/TasteMap.app
- Archive main CDHash: d0946c9a6ce4b1a0889d08f98e3d1c68996df843.
- Primary Web JS: index-DPEItTu8.js; SHA-256 752a885bf9df48a66a5bd5fec8aa8a4cd10c3bdf02263b04388ce71c2d70919b.
- Intermediate DeviceBuild artifact is not the designated install artifact.

## Verification

| Gate | Result | Evidence under /tmp/tastemap-cutover.GEkdto |
| --- | --- | --- |
| Source Web/Worker suite | 1561 PASS, zero failures | source-identity-final.log |
| TypeScript and clean formal Web build | PASS | stage.log |
| Swift bridge | 42 PASS | swift-package.log |
| Capacitor Photo Delete and no-delete Map/List/Map control | 2 PASS, zero failed/skipped | photo-capacitor.xcresult |
| Release signed device compile | PASS | device-identity-build.log |
| Archive | PASS | archive.log |
| Main and Share Extension identity/signature/device coverage | PASS | archive-identity.json |
| Release capabilities | PASS | archive-capabilities.json |
| Internal Release purity | PASS; no QA credentials/bypass, signed local UI | explicit --internal formal scanner |
| dist/staged/archive Web byte parity | 26/26 PASS | formal stage verifier |
| Release Simulator cold launch | Rendered real unauthenticated login UI; no fixture injected | release-cold-launch.png |
| New physical-device smoke | PARTIAL: overwrite, launch identity, automatic sync and preservation PASS; interactive UI smoke pending | /tmp/tastemap-0907-install.rUANDh |
| TestFlight upload | NOT RUN | physical-device gate remains open |

Full Native historical baseline comparison remains NO NEW REGRESSION, not all-green:
49 identical baseline failure IDs and two historical skips, documented in the
personal-filter checkpoint. This run does not relabel those as passing.

## Scope and preservation

Release root selection and shared route ownership now follow the authorized
cutover. Ordinary Universal Links forward to the existing parser; Referral remains
closed. Internal compile condition only selects Development API/account environment,
not DEBUG, QA or Sandbox purchasing capabilities. Ordinary Release retains Production.

The first build exposed missing generated custom Info.plist identity keys. Fixed
with an app-target-only ReleaseIdentity.plist and explicit build settings; rebuilt
and re-audited before installation. No signed artifact was patched in place.

SyncEngine, SyncCoordinator, PhotoTransferCoordinator, worker/syncV1 and
worker/photoBinaryV1 still match the accepted 8567035 implementations. Existing
Development migrations/deployment were not repeated. Production and real iPhone
were not modified during this candidate preparation. No real photo, Gift, Offer
code, account switch or purchase was used.

## Design system compliance

Core shell and canonical shared React templates retained; no formal map layout,
Food/Dining visuals, image priority policy or page-local design scale added.
Native MapKit and typed handoffs remain. No new duplicate product page introduced.
Previously implemented personal filters are bundled but require physical-device
visual confirmation; Simulator auth bootstrap is not full visual acceptance.

## Next

### Real-device installation checkpoint — 2026-09-09 21:18–21:21 Asia/Shanghai

User saved edits and unlocked the specified iPhone 17 Pro Max. The other connected
iPhone 12 and the separate com.lafayette.tastemap.qa installation were not touched.
Freshly resolved main-app PID 17589 matched installed 2026090906's bundle URL.
The process was briefly suspended for a consistent DB/WAL/SHM plus Photos backup
and resumed by an EXIT trap. Local backup integrity was checked with immutable
SQLite access after the standalone WAL-mode copy rejected plain read-only access.
No device database repair or modification was performed.

Private evidence/backup: /tmp/tastemap-0907-install.rUANDh (private directory).
Overwrite installed the designated archive App. Device inventory confirms
2026090907. Before launch, consistent DB and all nine local photo files were byte
identical before/after install. One normal launch succeeded at approximately 21:20;
PID 17797 emitted build 2026090907, the recorded commit/source fingerprint,
renderer=HYBRID_PRIMARY and referralAvailable=false. No signing rejection occurred.

Authoritative entitlement refresh reported refresh_verified; automatic normal
sync reported pass_end. A fresh post-launch DB snapshot passed integrity check.
Pending work remained zero. Seven resolved mutation audit rows (3 accept_server,
4 canonicalized) were preserved. Counts stayed 28 Restaurants, 27 Visits,
4 PhotoAssets, 5 Dishes, 2 Lists and 2 ListItems under the same existing Visit owner.
Full row comparisons for those tables and mutation audits had zero differences.
The existing two test Visits and remaining test photo were not cleaned up.

This proves installation, runtime build/mode identity and preserved local data,
not interactive Map/filter/account-screen acceptance or the new bounded
create/delete smoke. No logout, account switch, purchase or photo operation was
performed. Production unchanged; TestFlight not uploaded. Console collection
continues in launch-console.log while the launched app runs.

User subsequently confirmed “都对的” in response to the two explicit checks:
the visible account/history remain correct, and Discovery → For You filters show
预计喜欢度 and 口味匹配度 without 大家评分. These two real-device checks are PASS
based on user observation on installed 2026090907, not an independently captured
screenshot. This does not imply Map gestures, Visit creation or Photo Delete were
retested on this build.

User then confirmed “正常” for the explicit Map gesture/return-path checklist:
continuous pan/pinch, Restaurant Detail → Back with viewport retained, and
Map → List → Map without obvious stutter, white screen or unresponsive controls.
These checks are PASS based on user observation on 2026090907. No screenshot or
instrumented frame-rate result is claimed.

Next complete bounded Visit and Photo Delete smoke and reopen verification.
Preserve the pre-existing two Visits and remaining test photo. Do not upload
TestFlight until the fresh physical-device gates pass.
