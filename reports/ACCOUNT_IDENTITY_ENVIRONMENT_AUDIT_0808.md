# Read-only account/environment audit — 2026-09-08

## Finding
The local Lafayette profile and the newly authenticated Production profile are different internal Taste Map users bound to the SAME Apple provider subject. Exact provider subjects were compared privately and are not included in this report.

- Original owner digest: 8eb2e23cde. Exists in Development, nickname Lafayette, created 2026-09-04 00:54:29 UTC; last Apple authentication 2026-09-08 05:27:07 UTC.
- New owner digest: f02e1dc49d. Exists in Production, nickname Taste Map 用户, created 2026-09-08 10:58:25 UTC; last authentication 10:58:37 UTC.
- Current 0808 signed API target: https://api.tastemap.cn. Source/parser correction made this target usable; prior credential belonged to Development and was rejected by Production refresh.
- authV1 looks up Apple provider_subject inside the selected database and creates a random tm_ user when missing. Independent databases do not share user/session identity.

## Retained data, observed counts
Local device store (copied store+WAL+SHM for read-only inspection): original owner has 27 non-deleted restaurants and 24 non-deleted visits. Development cloud original owner: 25 non-deleted restaurants, 9 non-deleted visits. Production new owner: 0 restaurants, 0 visits. Counts differ; do NOT assume all local data is cloud-backed or overwrite either dataset.

## Actions
Read-only D1 SELECT queries and read-only device copy only. No database writes, user relinking, environment switch, install, app relaunch, merge or deletion during this audit. Private local preservation directory `.private/data-preservation-0808`; private query evidence `.private/account-identity-audit`.

## Gate
Data absent from current UI is explained by environment/account scope separation, not deletion of the verified original restaurant/visit records. Keep source data intact. Restoring the Development workspace view and transferring original data into Production are different actions; neither is authorized by this audit alone. A cross-environment migration must preserve unsynced local rows and use verified ownership, not email-based matching or blanket owner-ID reassignment.


## Authorized recovery — build 2026090809
After Lafayette explicitly requested direct recovery, the Private Preview compilation branch now selects the original Development API. Keychain credential namespace derives from the selected API environment, so the existing Development credential can restore without transmitting the Production credential to another server. The current private local store namespace stays unchanged deliberately: it contains the 27 original restaurants and 24 visits. No owner rewrite, database replacement or server migration occurred. Non-Private formal Release still uses the signed Production API resource; five production configuration tests PASS. Private-branch compilation test confirms Development API and unchanged persistence namespace.

Installed and launched exact `Taste Map Private` / `DebugPrivatePreview` artifact 2026090809, source fingerprint f173901634299d13b41fb9dd2d3a3489f5b93dde4c48c032eff0fb3cc427e32f. Signed main/extension identity PASS; 29 resource matches, 59 file sensitive scan PASS. Device log at 19:10:45 and 19:10:46 local shows entitlement refresh_verified; sync passes complete, with no auth failure in captured launch interval. Device store after launch retains 27/27 restaurants and 24/24 visits under the original owner. UUID set comparison against preserved pre-recovery copy: zero original active records missing.

Current scope is Private QA recovery only. Production data migration and full device visual/core smoke remain separate gates. No claim that cloud has every local record. Private data copies remain outside Git. UI appearance has not been independently captured in this recovery turn.
