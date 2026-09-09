# 2026090909 — authenticated owner photo resource recovery

## Scope and cause

0908 real-device Visit Editor displayed a broken image for a cloud-synced owner
PhotoAsset whose local cache paths were absent. The Hybrid owned-photo resource
handler only loaded local files; it did not call the existing authenticated
PhotoTransferCoordinator download/cache path. This is a resource-resolution bug,
not evidence of a missing cloud original.

Read-only Development R2 downloads of the affected display and thumbnail are
valid JPEGs and byte-identical to the pre-0908 private backup. No photo was deleted
or re-uploaded to mask the failure. Production was not accessed or modified.

The shared TasteMap/Photos directory also serves two retained database stores.
Single-store orphan cleanup could remove the other store's cache. Exact historical
deletion timing was not instrumented. Cleanup now conservatively defers when both
stores exist; explicit PhotoAsset deletion remains effective. This deliberately
retains potentially unreferenced files rather than inferring ownership from an
incomplete store. Neither database nor its mutation queue is merged or cleared.

## Repair

- Owned resources use the existing local-then-authenticated-download coordinator.
- The coordinator and handler share the main model context for cache persistence.
- Owner, active session and tombstone checks remain mandatory before delivery,
  including after the asynchronous download. Public-photo authorization is unchanged.
- QA HTTP content fixtures remain inside the existing DEBUG-only test fixture.
  No credential is added to a shipping path.
- UI layout, Auth business logic, normal Sync conflict handling and API selection
  are unchanged by this repair.

## Candidate identity

- Build: 2026090909 (Internal Development API candidate, not Final RC).
- Git HEAD: 9859b8cbc99e65984c8cfd935b2ec82a4e2be2a8 plus integrated working tree.
- Build-input fingerprint: 8a0290fb0e4a2b4177edfcdf8e9df973f0baec8e45b914a8419bf3c849a14bf1.
  Computed before this evidence report was added.
- Evidence root: `/tmp/tastemap-0909-photo.fu4yfW` (local private evidence).

## Verified before archive acceptance

- Full source suite: 1563/1563 PASS, 184 files.
- Native photo/Sync targeted: 37 cases, 50 parameterized executions PASS.
- Native isolated session/resource runtime: 8/8 PASS, including authenticated
  uncached download, persisted cache, other owner, missing photo, deleted photo
  and signed-out cache rejection.
- Formal TypeScript/Web stage: PASS; 26/26 staged assets byte-identical.
- Real Development display/thumbnail binary recovery: PASS, backup byte parity.

Signed archive completed successfully. Capacitor control Map/List/Map and Photo
Delete Map/List/Map: 2/2 PASS, zero failures/skips (xcresult summary). Release
purity PASS, staged/bundled asset parity 26/26 PASS, main app and Share Extension
signed identity/provisioning PASS for the requested iPhone UDID, capability audit
PASS. Archive: `/tmp/tastemap-0909-photo.fu4yfW/TasteMap-2026090909.xcarchive`.

Real-device image display remains PENDING until this exact
candidate is installed and the affected image is visibly verified. Metadata or
automated tests alone must not close that gate. TestFlight remains blocked.

## Data and installation boundary

### Real device checkpoint, 2026-09-09 22:13–22:21 +0800

0909 overwrite install and launch PASS on iPhone 17 Pro Max. Installed app
inventory confirms build 2026090909. Backup and after-install evidence are in
`/tmp/tastemap-0909-install.qwOjMR`. Business records and mutation rows unchanged;
normal pre-install background refresh updated sync checkpoint/cache/history, so
the entire active SQLite file is not claimed byte-identical. Alternate database
snapshot and existing photo files remained identical.

Through real iPhone Mirroring, opened 凯旋门商业中心店 and the 0907验收 Visit:
Restaurant user-photo thumbnail PASS; full-size gallery PASS; original failing
Visit Editor 本次照片 thumbnail PASS. Cancelled editor without saving any changes.
After this real UI read, display and thumbnail files exist in the device cache
and match the independently recovered Development R2 bytes exactly. Active queue
remains zero, 28 Visits and 5 PhotoAssets retained, seven resolved audit records
retained. No photo deletion/re-upload was used. This closes the reported image
display failure; this checkpoint does not claim a new process-restart test or
full Final Integration/TestFlight acceptance.

Retain both stores, WAL files, photos and outboxes in a fresh pre-install backup.
Overwrite installation only; no uninstall, account switch, forced conflict
resolution, photo recreation or Production deployment. Do not interrupt an
unsaved Visit editor. The alternate Development store's ten unresolved mutations
are not part of this repair and must not be cleared.

## Design system compliance

### Restart and second normal sync, 22:27–22:29 +0800

Closed the read-only editor before terminating only the resolved main-app PID
17865. Relaunched the same installed 0909; Hybrid Map rendered and account visible
ID 975844754787 remained unchanged. Reopened the same restaurant via Profile:
restaurant cover and user-photo thumbnail still display. Both cached JPEGs remain
byte-identical to the Development R2 copies after process restart.

Invoked Settings → 立即同步 once. UI reported 正常 and last success 22:29:13.
Post-sync device snapshot confirms active unresolved queue 0, seven resolved audit
rows, 28 Visits and 5 PhotoAssets. Evidence: after-restart-sync and its SQLite
snapshot under the installation evidence root. No new Visit, photo deletion,
logout/account switch or Production action performed at this checkpoint.

Remaining observed UI defect: the new Visit with no amount displays
`整桌 ¥undefined · ¥undefined/人` in Restaurant Detail history. Suspect shared
RestaurantPreviewCard visit-spend formatting checks only `!== null`, permitting
omitted optional DTO fields. This is separate from photo loading. Record it as an
open integration issue; do not claim full real-device smoke or TestFlight ready.

No Core UI, dining visual composition, canonical page template, typography,
layout or renderer change. Existing surface-specific owner/public/category
selection remains intact; only authorized image-byte retrieval is repaired.
