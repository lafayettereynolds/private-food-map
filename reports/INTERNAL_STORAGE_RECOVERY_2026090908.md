# 2026090908 — retain accepted local storage for Internal upgrade

## Photo display blocker — user screenshot at 21:54

User reports broken image in Visit Editor for the recovered photo. Therefore
photo visual recovery and full smoke are FAIL/BLOCKED despite metadata sync PASS.
The active PhotoAsset has storage keys but no local/display/thumbnail file paths.
Hybrid photoDescriptor emits tastemap-resource://photo/<id>/thumbnail, while
resourceData only permits network fallback for public-photo, not owned photo.
Thus an owned, cloud-synced photo with no local cache cannot render through this
route. Existing PhotoTransferCoordinator.imageData already has an authenticated
local-then-remote path, but this resource handler bypasses it.

The pre-0908 backup contains all three binary variants of the new photo. They
are absent from the post-restart live-directory copy. PhotoTransferCoordinator
has orphan cleanup based on the current store's references; a shared photo root
across the changed stores makes startup cleanup a relevant additional hazard.
Exact deletion timing is not instrumented, so attribute that mechanism as a
strong hypothesis, not a captured deletion event. No manual photo deletion was
performed. Original binaries remain in the private pre-install backup.

Do not ask the user to delete/re-upload/save the edit to mask this defect. Keep
TestFlight closed. Next bounded repair should use the existing owner-authorized
photo download/cache path and test missing-cache/restart/deleted/account-switch
cases; also audit shared-root orphan cleanup before further device installation.

## Scope

User authorized the bounded storage-selection repair and new candidate preparation.
No direct database merge, conflict clearing, owner rewrite or phone install is part
of this preparation. Production, Workers, D1 migrations and UI are unchanged.

AppEnvironment.current no longer includes TASTEMAP_INTERNAL_BUILD in its legacy
Development-storage condition. This restores the 0906 Private Preview namespace:
TasteMap.store, the accepted Premium cache and TasteMap/SocialOutbox. The explicit
Internal APIConfiguration branch remains Development at https://api-dev.tastemap.cn.
Auth credentials still select their service from APIConfiguration, not the storage
enum; no real Keychain was read by configuration tests. DEBUG and Sandbox keep
their separate Development stores. Ordinary Release retains its Production API.

A non-content container_open diagnostic records actual configurationName and API
environment after opening the container, preventing future snapshots from silently
checking a different database. No credential, user content or absolute path is logged.

## Verification

- Red/green compiled Swift test: old 0907 Internal condition failed the retained
  namespace assertion; fixed Internal passes.
- Compiled Internal, Private Preview, Sandbox and DEBUG matrix: four PASS.
- Ordinary Release API regression: five cases PASS, including invalid config
  fail-closed behavior and the actual signed source configuration.
- Full source suite: 1562/1562 PASS (183 files), no failures.
- Native Sync targeted: 39 test cases / 50 parameterized executions PASS, no skips;
  includes recovery, accept_server, legacy association and wire contracts.
- Formal TypeScript/Web build and dist/staged parity: PASS, 26 files.

### Real backup offline rehearsal

One-off isolated Native test used COPIES of the recovered old store and the active
0907 store. It constructed normal pull DTOs for the new synced Visit/photo, then
called unmodified SyncEngine.synchronize twice and reopened the target copy.

Result: 1/1 PASS; Visit/photo each appeared exactly once, same owner, old counts plus
one each, seven resolved audit records retained, zero push calls, reopen preserved
the additions. No network, real device or real database was written. The alternate
store's ten conflicts were not imported, cleared or force-resolved.

The one-off harness containing local backup paths was archived outside Git and
removed from the test source tree after execution; permanent configuration and
boundary regression tests remain. Evidence:
/tmp/tastemap-0908-storage.5uPR6J/replay.xcresult and LocalBackupReplayTemporaryTests.swift.

### Development persistence confirmation

Two scoped read-only primary-key queries in food-map-db-development confirmed the
new Visit and PhotoAsset exist, active, server_version=1. Photo original/thumbnail
keys exist. Each query read one row; zero rows written. This is server metadata
confirmation, not a fresh R2 binary download or a real-phone pull result.

## Candidate

- HEAD: 9859b8cbc99e65984c8cfd935b2ec82a4e2be2a8 plus preserved workspace.
- Build input fingerprint: d5bd2a5d374cd1c00d160680c954db341168fff162d9f34fcfbd100d222a75ed.
- Build: 2026090908; Release + ReleaseInternal.xcconfig; HYBRID_PRIMARY.
- Archive: /tmp/tastemap-0908-storage.5uPR6J/TasteMap-2026090908.xcarchive.
- Designated App: archive Products/Applications/TasteMap.app (no intermediate build substitution).
- Archive/Release signed build: PASS. Main CDHash: 429d0c5c3efd090193307c867da5a93ee8d5547a.
- Main and Share Extension signing/profile/real-device coverage: PASS (identity.json).
- Release capability audit: PASS (capabilities.json), zero errors.
- Internal purity scan: PASS, 55 app files / 26 signed Web files; no QA/auth bypass.
- dist/staged/archive asset parity: 26/26 PASS. Build fingerprint embedded correctly.
- READY FOR CONTROLLED OVERWRITE: YES, subject to fresh dual-store backup and user confirmation.
- Preparation initially left 0907 installed. User subsequently authorized installation;
  the real-device checkpoint below supersedes that preparation-only status.
- Real-device storage/sync recovery: PASS as scoped below; full smoke still incomplete.
- TestFlight NOT RUN.

## Authorized real-device installation — 2026-09-09 21:50–21:53 Asia/Shanghai

Target iPhone 17 Pro Max / CoreDevice 60BBB934-D441-53FB-B8CF-0E3DB5878C4D.
Fresh backup /tmp/tastemap-0908-install.w4jyUX includes the whole Application Support
directory: BOTH databases/WAL/SHM, photo and outbox directories. Both consistent
SQLite snapshots passed integrity checks. Original 0907 process PID was freshly
resolved as 17797, briefly suspended for copy and resumed by an EXIT trap.

The designated 0908 archive App passed fresh identity/profile/device coverage
checks and was overwrite-installed (no uninstall). Installed inventory confirms
2026090908. Installation-time directory comparison found only SHM differences;
both reconstructed full database snapshots were byte-identical, as were photo
files and other Application Support content.

Normal launch PID 17833 emitted the expected source fingerprint, HYBRID_PRIMARY,
and container_open name=TasteMap apiEnvironment=development. Entitlement refresh
verified; normal sync completed. The active TasteMap.store received the new
0907验收 Visit and its uploaded/synced PhotoAsset, both version 1 under the original
owner. No manual row copying or conflict resolution was used.

One controlled terminate/relaunch (PID 17837) and second automatic normal sync
passed. Fresh snapshot shows 28 distinct Visits, 5 distinct PhotoAssets (including
preserved tombstones), zero unresolved work, and the seven original resolved
audits (3 accept_server, 4 canonicalized). New Visit remains synced. The alternate
TasteMapDevelopment.store and WAL remain byte-identical to pre-install copies;
its ten conflicts were neither cleared nor declared resolved.

Evidence: console.log, restart-console.log, apps.json, both before/after consistent
snapshots and Application Support copies in the private install directory.
No Production writes, purchase, account switch or photo deletion in this step.
Next: visible new-photo confirmation and bounded Photo Delete smoke on 0908.

## Next gate

Before a separately confirmed overwrite, back up BOTH actual stores, WAL/SHM and
photo directories with a freshly resolved device PID. Never use the earlier
TasteMap-only backup script as proof of the active 0907 queue. After installation,
verify the new runtime logs name=TasteMap and apiEnvironment=development, then
same account, new Visit/photo recovery through normal pull, queue zero, old audit
preservation, restart/idempotency and no resurrection. Retain the alternate store
and ten conflict records as protected evidence; they are not declared resolved.
