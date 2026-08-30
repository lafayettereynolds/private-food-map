# Taste Map Task 02 Reopen — Real-device Sync Pull Timeout

Date: 2026-08-30  
Scope: Development `/api/v1/sync/pull` only  
Production access: **none**

## Acceptance state

- Before this fix: `AUTOMATION PASS / REAL DEVICE FAIL`
- After this fix: `AUTOMATION PASS / DEVELOPMENT E2E PASS / FINAL REAL DEVICE RETRY PENDING`
- Failure classification: **B — Worker received and authenticated the request, but hydration exceeded the client's request timeout**

## Root cause

The change-ledger query was indexed and fast, but the Worker hydrated every change with sequential D1 calls:

- one entity query per change;
- one additional place-identity query per Restaurant;
- more sequential queries for required Restaurant / Visit / Dish parents.

A first page containing 200 change events therefore produced hundreds of cross-service D1 round trips. The current Apple user's first page returned only about 163 KB, but its time to first byte was about 50.48 seconds. The iOS client correctly cancelled the request at its existing 15-second per-request timeout, so the app surfaced `pull → timeout` after roughly 17 seconds including coordination/diagnostic overhead.

This was not caused by Wi-Fi, cellular service, DNS, TLS, response download size, a missing change-log index, or a non-2xx response being misclassified.

## Pre-fix evidence

### Same current Apple user, anonymous Development-authenticated observation

- HTTP: 200
- DNS: 0.013 s
- TCP connect: 0.212 s
- TLS ready: 0.415 s
- TTFB: 50.483 s
- Total: 51.070 s
- Response: 162,763 bytes
- Page cursor: `0 → 3310`
- `hasMore`: true

### Comparable real-sized Development test identity

- HTTP: 200
- DNS: 0.100 s
- TCP connect: 0.295 s
- TLS ready: 0.503 s
- TTFB: 51.176 s
- Total: 51.674 s
- Response: 162,523 bytes

### Current Apple user counts (no business content or identity emitted)

- Restaurants: 121
- Visits: 279
- Dishes: 92
- Photo metadata: 0
- Tombstone change events: 1
- Total change events: 646
- Maximum Development cursor at observation time: 15951

The change-ledger query used `idx_sync_change_log_v6_pull (user_id, revision)` and a 200-event page query took approximately 0.14 ms in the D1 read-only preflight. The bottleneck occurred after that query, during sequential entity hydration.

## Cursor and checkpoint finding

- A new per-user `SyncCheckpoint` legitimately starts at cursor `0` when that user has no successful sync.
- Checkpoints remain scoped by `ownerUserID|sync-v1`.
- The Task 01 per-user ownership change did not select another user's cursor and did not use a legacy-unscoped checkpoint.
- Cursor `0` made the bug reproducible because it exercised a full first sync, but cursor handling was not the performance defect.
- A regression test now proves that user A resumes from its own cursor across multiple pages while user B's checkpoint is untouched.

## Fix

- Group the 200 ledger events by entity type.
- Read entity rows with owner-scoped `IN (...)` queries, chunked to 50 IDs.
- Submit each group through bounded D1 batches instead of one awaited request per record.
- Batch Restaurant place-identity reads.
- Batch required Restaurant / Visit / Dish dependency hydration.
- Preserve the existing cursor, owner isolation, tombstone, parent-hydration, response-contract, and 200-event page semantics.
- Keep the iOS 15-second request timeout, 60-second maximum backoff, 20-page pull budget, cancellation behavior, and single-flight coordination unchanged.
- Add Development-only structured pull telemetry and a safe `Server-Timing` response header. Telemetry includes timings, counts, cursors, response bytes, and status only; it does not include access tokens, user IDs, Apple subjects, or business content.

No D1 migration was needed.

## Post-fix Development measurements

Development Worker deployment version:

`3537088a-d348-47d5-999c-c0ee739ba619`

### Same current Apple user, cursor 0 through completion

| Page | TTFB | Total | Bytes | Items | Tombstones | Cursor | hasMore |
|---|---:|---:|---:|---:|---:|---|---|
| 1 | 1.848 s | 2.102 s | 162,763 | 198 | 1 | 3310 | true |
| 2 | 1.834 s | 2.434 s | 246,462 | 290 | 0 | 3510 | true |
| 3 | 2.167 s | 2.482 s | 246,526 | 290 | 0 | 3710 | true |
| 4 | 1.686 s | 1.687 s | 39,109 | 48 | 0 | 15951 | false |

The response item total can exceed 200 because relationship-safe parent records are included; the ledger page itself remains capped at 200 change events.

### Empty incremental pull after the final cursor

- HTTP: 200
- TTFB: 1.322 s
- Total: 1.322 s
- Response: 300 bytes
- Items: 0
- Tombstones: 0
- Cursor remained 15951
- `hasMore`: false

### Representative server timing, page 1

- Auth: 161 ms
- Profile bootstrap/read: 154 ms
- Ledger query: 183 ms
- Batched hydration: 798 ms
- Response assembly/encoding: below the two-decimal telemetry threshold

Cloudflare tail creation succeeded during the investigation, but the local streaming transport was intermittently disconnected by network `ETIMEDOUT`. The Worker-emitted `Server-Timing` values and successful HTTP responses provided the same stage-level server observation without exposing credentials or PII.

## Regression coverage

- Real-sized 200-change pull page.
- Bounded hydration query budget (at most 10 local query executions for the 200-Restaurant fixture instead of approximately 401).
- Incremental cursor returns no unchanged records.
- Empty mutation queue still pulls.
- Per-user checkpoint resumes from the correct cursor.
- Another user's checkpoint is unchanged.
- Existing 15-second request timeout remains bounded.
- Existing retry/backoff remains bounded.
- Existing actor/coordinator single-flight tests remain passing.
- Existing Restaurant / Visit / Dish / Photo / list / tombstone / identity compatibility tests remain passing.

## Verification

- TypeScript typecheck: passed.
- Vite build: passed (existing chunk-size warning only).
- Worker/Web Vitest: **49 files, 341 tests passed**.
- Focused Sync + Restaurant List integration: **33 tests passed**.
- Development Node Sync E2E against `https://api-dev.tastemap.cn`: passed.
- iOS native URLSession → Development Worker → D1 E2E: passed, 9.796 s.
- iOS SyncCoordinator focused suite: passed, including the new per-user paged checkpoint test.
- iOS Debug Simulator build: passed.
- iOS Release Simulator build: passed.

## Safety

- Production Worker: not accessed or modified.
- Production D1: not accessed or modified.
- Production R2: not accessed or modified.
- Development D1 schema: unchanged.
- iOS production sync behavior: timeout, retry, checkpoint, cancellation, auth, and sync contracts unchanged.
- Existing unrelated `project.pbxproj` and untracked files were not included.

## Remaining manual acceptance

No new iOS build is required because the runtime fix is in the already-deployed Development Worker; the only iOS source change is regression-test coverage. The currently installed candidate can perform one final real-device **Retry Sync**. That single action is acceptance confirmation, not further diagnosis.
