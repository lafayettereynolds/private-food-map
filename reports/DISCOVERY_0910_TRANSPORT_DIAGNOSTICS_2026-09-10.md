# Discovery 0910 transport diagnosis

## Observed evidence

Real build 2026090910 reported URL errors -1005/-1001 on 2026-09-10 around 06:01–06:12 GMT+8. User subsequently reported spontaneous recovery. Existing Sync/entitlement successes are not proof of Discovery transport success.

Read-only Development dashboard inspection (Worker version 581b3f08-fc17-44f6-a089-c7d720d73769):

| Time GMT+8 | Invocation | HTTP | CPU ms | Wall ms |
|---|---|---|---|---|
| 06:06:50.180 | 3fc1825e6fe6f504f17c36d6e8bd9db0 | 200 | 18 | 2565 |
| 06:07:25.494 | 5d177be568d677f7eb4e7c6fcb9565a8 | 200 | 9 | 2411 |

Both are city-scoped For You GET requests using HTTP/3, TLSv1.3, AMS colo and Hangzhou Telecom access networks. Successful Worker execution does not prove the phone received its response. There is no exact common request identifier in the old client error log. HTTP/3 or VPN causation remains unproven. The 06:11:10 error invocation ce4b0a309b9680fd3eeb56be1cea9022 is the unauthenticated diagnostic probe, HTTP 401, not a failing authenticated recommendation query.

## Scoped source change

DiscoveryAPIClient now observes each task using the existing injected URLSession and a task-scoped delegate. Each attempt records a random local correlation ID, elapsed time, status, allowlisted Cloudflare Ray ID, protocol, connection reuse and proxy flags. A Ray ID is available only when response headers were received. No URL/query, response body, bearer token, user ID or address is logged. The existing bounded DeviceAcceptanceLog sink is reused.

No automatic retry, new session, server/endpoint change, authentication override, recommendation change, timeout change or protocol downgrade was added. This is diagnostic instrumentation, NOT a proven transport fix.

## Verification

- Isolated Simulator compile and three Discovery suites: 24 tests PASS.
- Includes failure identity preservation, exactly one request on connection loss, existing authorization header preservation, Ray/protocol sanitization, paging/filter/cache/access regressions.
- Command: xcodebuild test; TasteMap scheme; isolated Simulator 937E1937-2EBB-45DF-B762-E32C11F0A5D2; derived data /tmp/tastemap-discovery-diagnostics-build; parallel testing disabled.
- Log: /tmp/tastemap-discovery-failure.VlxBts/discovery-regression.log.
- Full suite / Release archive / signed diagnostic build: NOT RUN in this change.
- Real-device diagnostic instrumentation: NOT INSTALLED. Existing 0910 remains unchanged.
- Product UI/banner fix: NOT IMPLEMENTED; separate remaining defect.
- Production, Worker deployment, real iPhone data/settings: NOT MODIFIED.

Next: package and verify a uniquely identified diagnostic candidate before installation; correlate future failing tasks with Worker Ray IDs where present. Do not claim permanent resolution from recovery or these Simulator tests.

## Signed candidate 2026091011

- Release Internal archive completed. API remains https://api-dev.tastemap.cn; Hybrid primary renderer retained.
- HEAD 9859b8cbc99e65984c8cfd935b2ec82a4e2be2a8 plus preserved integrated workspace. Source fingerprint 3d73c8aa67cc352a82b2a19ec1a29f34be863438391a36b838f0e42469c24193 (existing git-index/untracked nonignored files, sorted path/NUL/bytes; tracked deletions omitted).
- Main App and Share Extension identity/signature/provisioning/device authorization PASS for 00008150-00181DC90184401C. Deep strict codesign verification PASS.
- Release capability audit PASS; Internal purity PASS, no QA fixture/auth bypass.
- dist/staged/built resource parity 26/26 PASS. Existing 0910 archive also matches these same resources: no Web UI change included.
- Evidence root /tmp/tastemap-discovery-1011.trRoeJ; archive and audit copy retained under Git-ignored .private/releases/2026091011.
- READY FOR REAL DEVICE INSTALL: YES. Actual installation/runtime verification: NOT PERFORMED.
- No TestFlight upload, Production deployment, device mutation, account logout or Sync execution performed.
- This candidate adds diagnostics only. Network root cause and banner obstruction remain OPEN. Before any overwrite installation, preserve current App data and verify current pending mutations; do not assume yesterday's zero queue still holds.
