# Final Integration — current 0910 device checkpoint

2026-09-09 22:52–22:56 Asia/Shanghai. Current installed candidate is 2026090910,
not the superseded 0907/0908. See INTERNAL_SPEND_LABEL_2026090910.md for exact
archive, source fingerprint, tests, install backup and signing evidence.

## Current bounded acceptance

- Internal Development API; HYBRID_PRIMARY with retained Native rollback.
- 1569/1569 source Web/Worker tests PASS; TypeScript PASS.
- Signed archive, capabilities, extension identity, purity, staged/built 26/26 PASS.
- Overwrite/launch, same visible account, preserved data and pending queue 0 PASS.
- Owner photo gallery and Visit amount missing/recorded contrast PASS.
- Real Map → List → Restaurant Detail → Back restores List; List → Map PASS.
- Real Discovery filter sheet visibly contains independent 预计喜欢度 and
  口味匹配度 fields; shared quick controls match. Cancel retains conditions.
- Map accepted mirrored pan gestures, but their velocity/inertia moved far from
  the starting viewport. Do not call this quantitative viewport restoration,
  frame-rate, or physical two-finger pinch/smoothness acceptance.

Earlier Sync recovery and real Photo Delete acceptance remain valid historical
evidence for their respective builds. 0909 process restart + manual sync and
cache persistence are specifically documented for 0909, not silently reassigned
as new 0910 executions. Native full-suite evidence remains NO NEW REGRESSION with
49 known baseline failures and two historical skips, not an all-green claim.

## Remaining current-build gate

Final real-device smoke is PARTIAL. This checkpoint has not executed a new
0910 Visit creation or Photo Delete, nor completed 0910 restart/second-manual-sync
and final physical map-handling review. The original Final Integration request
explicitly retains the two existing test Visits and remaining test image until
after smoke; they are not disposable cleanup targets. A separate disposable
photo is needed if performing a fresh deletion on 0910. Do not clear queues,
delete protected tests, or reuse historical evidence as a new physical result.

INTERNAL TESTFLIGHT UPLOAD: NOT RUN. Production/DNS/migrations unchanged.
No new product-layout change was made during these read-only navigation checks.
