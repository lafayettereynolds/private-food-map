# 0910 Final Integration release gate — 2026-09-09

## Identity and preservation

- Protected integration input: `/Users/lafayette/Projects/tastemap-final-freeze.4LXM27/workspace`.
- Branch feature/hybrid-final-integration; HEAD 9859b8cbc99e65984c8cfd935b2ec82a4e2be2a8 plus integrated workspace.
- Source fingerprint embedded in 0910: 30946c8f83726dc040f98d408179963383539302c82e2615528cc57dac8b34b7.
- Archive: `/tmp/tastemap-0910-spend.85YIE0/TasteMap-2026090910.xcarchive`.
- Installed/tested version 1.0 (2026090910), com.lafayette.tastemap, iPhone 17 Pro Max,
  UDID 00008150-00181DC90184401C. HYBRID_PRIMARY; Native rollback preserved.
- Internal API https://api-dev.tastemap.cn. Production untouched.

## Gate decisions

Integration/Sync recovery/Photo Delete/Discovery/Auth lifecycle/StoreKit environment:
PASS under the integrated automation and historical targeted evidence, with no
new Native regression. Native historical 49 failures and two skips remain explicitly
accepted baseline exceptions, not fabricated all-green results. Source Web/Worker
1569/1569 PASS; TypeScript, Release Archive, purity and assets PASS.

Development 0040 dependency resolved previously. 0041 Discovery and 0042 Photo
Delete identities/ledger retained; not rerun. See FINAL_INTEGRATION_DEV_DEPLOYMENT.

User explicitly reports the final 0910 create/save/restart/normal Sync, final
restart/account/Visit persistence/deleted-photo non-resurrection/second Sync and
final real map feel PASS. These are USER-PERFORMED REAL DEVICE evidence, not claimed
agent gesture observations. Agent's 0910 rendering, navigation and data checks
are in the companion checkpoint/spend reports. No repeated StoreKit purchase.

## Final data verification

Fresh device Application Support snapshot and standalone DB backup under evidence
root `final-device`: integrity PASS, 29 Visit rows, single owner, active queue 0,
seven resolved recovery audits. Prior Visit IDs all retained; no duplicate remote
Visit IDs. New test Visit 96361FB6-32E3-460E-9F41-03F99BCC7D17 initially synced v2.
During verification it transitioned to deleted at 23:07:40.941 +0800. Read-only
targeted cloud query and subsequent local DB/WAL copy both confirm the same
deleted timestamp and synced v3, still queue 0. Do not claim it remains active.
The earlier protected Visits/photo were not deleted by this task.

New test photo f36a878f-fc8f-4b4f-90ed-fa047b1b5dd0 is locally synced/deleted with
binaryDeletedAt. One scoped Development D1 query confirms deleted_at; exact-key
Development R2 probes for display/original and thumbnail both return key does not
exist. No remote write was used for verification. User confirms restart no
resurrection. No silent loss/duplicate/owner change found.

One whole-directory recheck was blocked by iOS file protection on unrelated
SocialOutbox. Retried only the target database and WAL successfully; no permission,
trust or account setting was modified. The initial full backup remains available.

## Distribution export/signing

Exported from the SAME archive, without build/version management or recompilation.
app-store-connect method; testFlightInternalTestingOnly=true; automatic Apple
Distribution signing for team 7G5J9MJX88. Certificate SHA1
21D2BBB03006B9A8DA5337AC3FDB32C9F1B4AE4A, expires 2027-08-27.
Main + Share Extension signed/profile entitlement and nested signature checks PASS;
get-task-allow=false, beta-reports-active=true. Main and extension build remain0910.
Exported purity and staged/bundled assets 26/26 PASS. Archive/export Mach-O UUID
matches: 4EFA500B-8770-3A7C-BFB7-8833D2655447. Embedded source identity/API match.
Development device profile is not reused as a distribution profile.

Local exported IPA SHA256:
92ff0fa5d4f9d75d014525fb635b48513d156b8fcf14ec0c0d62b462b9288069.
IPA is `/tmp/tastemap-0910-spend.85YIE0/distribution/TasteMap.ipa`.

FINAL INTEGRATION / REAL DEVICE SMOKE / DISTRIBUTION EXPORT: PASS.
Upload authorized after these gates. INTERNAL TESTFLIGHT UPLOAD: PASS.
Xcode upload at 23:16:25 +0800 returned `Upload succeeded`, `Uploaded TasteMap`
and `EXPORT SUCCEEDED`; the preceding Apple response says uploaded package is
processing. Apple processing/internal install availability is PENDING, not inferred
from transport success. The signed-in App Store Connect TestFlight page loaded
its header but not the build list during the immediate check. One refresh then
returned the Apple login page with authResult=FAILED, so browser authentication
is required to inspect final processing/availability. This is independent of the
successful Xcode upload receipt. No testers/groups,
external testing or store release settings were changed.

Durable local artifact copy (Git-ignored): `.private/releases/2026090910/` contains
the original xcarchive, exported IPA, export/upload options, distribution checks
and upload receipt log. Sensitive device backups stay in the private temp evidence
directory and are not committed. No source rebuild or build-number change occurred.
No external beta/App Store release or Production operation authorized/performed.
