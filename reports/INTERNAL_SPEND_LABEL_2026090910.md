# 0910 — missing Visit amount presentation

## Observed and reproduced

On installed 0909, the new 0907验收 Visit has no recorded amount. Restaurant
Detail history showed `整桌 ¥undefined · ¥undefined/人`. Native JSONEncoder omits
nil optional fields; the shared label only tested `!== null`. Omitted fields and
explicit null must have identical missing-data semantics under the existing
Visit Editor product contract.

## Bounded repair and consumer inventory

Moved the shared history formatter into existing visitSpend.ts, reusing its
finite/nonnegative money validation and unchanged actual-spend resolver. Missing
amount shows 未记价格; real zero remains zero. No database, calculation, owner,
Sync, Auth, Photo, API, renderer or layout behavior changed.

RestaurantPreviewCard owns the matching summary for Browser Map preview/detail,
standalone detail, Community detail and Hybrid detail. All consume the same
formatter. Native RestaurantDetailComponents uses optional binding for its
actual-spend summary and does not interpolate JS undefined. The database's
price-reference filtering is a different semantic consumer, not a history label.
No new duplicate UI or page-local visual tokens were introduced.

Core UI and canonical Restaurant Detail template unchanged. Food/Dining visuals
unchanged. Existing amount-field rule remains: no calculation hints added.

## Tests and artifact identity

- Full Web/Worker source suite: 1569/1569 PASS, 184 files.
- Added missing/null, explicit zero, treated, personal payment, unresolved table,
  AA, reference and invalid amount cases plus actual shared-card rendering of
  omitted Native keys. No skips or relaxed expectations.
- TypeScript + formal Web stage PASS, 26/26 staged asset parity.
- HEAD 9859b8cbc99e65984c8cfd935b2ec82a4e2be2a8 plus preserved workspace.
- Build-input fingerprint 30946c8f83726dc040f98d408179963383539302c82e2615528cc57dac8b34b7,
  computed before this report.
- Internal Development candidate build 2026090910. Evidence/archive root:
  `/tmp/tastemap-0910-spend.85YIE0`.

Archive, capabilities, main/Share Extension signing/provisioning, Internal purity
and built/staged asset parity (26/26) PASS. Complete Application Support backup
preceded overwrite installation. Installed inventory confirms 2026090910.

Real iPhone Mirroring at 22:49 +0800: the unchanged 0907验收 Visit shows 未记价格;
the older Visit shows 我的消费 ¥18. Both appear together in the real Restaurant
history, with photo still displayed. No Visit was edited to produce the result.
Post-install integrity PASS, 28 Visits, 5 PhotoAssets, active pending queue 0,
seven resolved recovery audits retained. Runtime acceptance for this formatter
fix PASS. Full Final Integration is not inferred from this bounded check.
Production and TestFlight remain untouched.
