# Production RC 1.0 (2026091012)

## Frozen source

- Independent branch: `release/production-rc-20260910`.
- Current integration workspace copied without changing that workspace: freeze commit `ed9cd8d` (2,133 source files; snapshot SHA-256 `5fa93543ed7a06d5c51479f0c6b2fb7f2125443037afed36648664efe4ab9a26`).
- Production Worker isolation `fc148340` applied as `ffe477b`; no Worker redeployment.
- Personal rating precision `fbad2bd` applied as `21a369c`. The two append-position conflicts retained both current integration tests/product rules and the new precision additions; no current auth, Sync recovery or Photo Delete implementation was replaced.
- Clean formal Web staging committed as `0ee4f9cf50d35cac326b33d903cab354aaad62f3`.
- **Archive source fingerprint:** `6f4663fb5ccc02b78910443333e967265b21987378bb9e2c5a23a325ecc5fa39` (2,142 tracked files, sorted path + NUL + file bytes).
- Version `1.0`, build `2026091012`, bundle `com.lafayette.tastemap`, team `7G5J9MJX88`.

## Configuration and upload contract

- Formal Release, `HYBRID_PRIMARY`, Native rollback preserved.
- Embedded distribution channel `production`, API `https://api.tastemap.cn`.
- No Internal/Private Preview/Sandbox xcconfig override.
- Normal `app-store-connect` distribution; **`testFlightInternalTestingOnly=false`** in both export and upload options; automatic build-number management disabled.
- Only existing **Internal Testers** group (`isInternalGroup=true`) is in scope. No external group, public link, beta review submission, App Review submission or automatic release is authorized.
- Old build `2026090910` is verified by ASC as `INTERNAL_ONLY`; it is not reused as this RC.

## Automated evidence

Private evidence: `.private/rc-evidence/` (not committed).

| Gate | Result |
| --- | --- |
| Web/Worker full suite | 1,584/1,584 PASS; zero failures/pending |
| TypeScript | PASS, formal staging prerequisite |
| Swift bridge package | 43/43 PASS |
| Native full suite | 858 passed / 49 failed / 2 skipped, 909 total |
| Native no-new-regression | PASS: exact same 49 failure identifiers and two skips as approved 904-test baseline; zero new failures |
| Clean formal Web stage | PASS, 26 files byte-identical |
| Signed Release Archive | PASS |
| Archive / Distribution resource parity | PASS, 26/26 in both |
| Archive / Distribution purity | PASS, 55 app files / 26 signed Web files; Production mode |
| Main + Share Extension signed identity | PASS, same build; Distribution `get-task-allow=false`, `beta-reports-active=true` |
| Archive / exported executable UUID | Identical: `5AF4E1B5-73B7-337B-BC28-C43861DE8E13` |

Historical Native failures are explicitly retained baseline debt, not a full-suite PASS. No assertions were weakened or tests disabled. Simulator tests do not establish physical-device Product/visual acceptance.

The local Capacitor origin's `hostname=localhost` is the existing signed local UI host, not a remote UI server, API fallback or test identity. Production API and absence of `server.url` were checked separately.

## Apple and backend read-only checks

- Production `/health`: 200.
- Production and Sandbox notification URLs both `https://api.tastemap.cn/api/v1/storekit/notifications`, both versions `V2`, read from App resource (not inferred from a test notification). No configuration changed.
- Monthly and annual ASC product IDs match Native and Worker configuration. Both ASC product resources currently say `MISSING_METADATA`; first-subscription metadata/review remains a later prerequisite, not silently marked ready.
- Real StoreKit product load on this TestFlight build remains unverified. TestFlight transaction environment is not reclassified as Production merely because the app uses Production API; existing server environment isolation remains intact.

## Device preservation and pending smoke

- Before installation, device inventory confirms current installed build `2026091011` on iPhone 17 Pro Max.
- Copied Application Support DB/WAL/SHM and App Group Library read-only to private evidence. Both stores pass integrity checks; private inventory records IDs, owners, counts and file hashes.
- `TasteMap.store`: 29 Visits / 6 PhotoAsset records; 7 historical conflict rows have `accept_server` (3) or `canonicalized` (4) audit resolution, **active queue 0**.
- Separate legacy `TasteMapDevelopment.store` retains 10 unresolved rows. It is not cleared, merged, or used to claim the current queue is nonzero. Formal Release selects `TasteMap.store`.
- No app uninstall, local data clear, logout/account switch, genuine photo deletion or Production database write has been performed by this RC build task.
- TestFlight installation, launch/auth/map/detail/new dedicated test Visit/Sync/test photo upload+delete/R2 original+thumbnail deletion/restart/queue0/Premium product load remain **NOT RUN** on build 1012 until actual device evidence exists.
- **APP REVIEW CANDIDATE: NOT YET.** Same-build eligibility and successful upload do not substitute for Production smoke.

## Upload state

Upload started using the above normal App Store Connect options. Final transport, processing, build audience and internal group membership must be confirmed before reporting availability.
