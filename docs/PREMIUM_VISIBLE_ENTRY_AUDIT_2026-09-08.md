# Premium visible-entry audit — 2026-09-08

## Scope and implementation

Free users retain named locked entries; protected values and actions remain gated. Shared React changes cover Browser and Hybrid profile analysis links, monthly/yearly cards, companion/source entry labels, analytics data/poster locked landing, same-taste discovery, map filter chips, same-taste rating, dish photo actions, exhausted photo allowance and daily roulette. Native rollback changes cover entitlement badges, source/companion filters, same-taste rating, dish upload and roulette restrictions.

The source-analysis entry explicitly mentions 最坑推荐来源. No free analytical results are rendered behind the locked landing. Free dish text entry remains available immediately beneath 本次照片. Editor grid tracks use intrinsic content height to prevent the dish section collapsing.

## Verified evidence

- Six targeted suites: 20 tests passed (labels for paid/free/loading, filters, ratings, dish editing, photo allowance and roulette).
- Formal bundle stage: 26 files byte-identical; final built QA app: 26 files byte-identical.
- Xcode DebugQA build succeeded. App installed on iPhone 17 Pro simulator E4F3EED9-89D8-405C-B4CB-7CA816CE3405.
- Source branch feature/hybrid-final-integration, base 58bd556, existing shared worktree changes preserved.
- Runtime: com.lafayette.tastemap.qa, React Hybrid with Native MapKit; launch --tastemap-hybrid-development -AppleInterfaceStyle Light, TASTEMAP_VISUAL_QA_MODE=free.
- Profile showed account 553453737518, 开通 Premium and visible locked taste/month/year cards.
- Clicking taste entry opened Premium. Map source/companion/exact-source chips stayed visible with locks and More. Clicking locked companion opened Premium with the originating filter sheet dismissed in the final build.
- Restaurant detail showed locked 同味评分 without its protected number/count, while the other three rating groups and photos remained.
- Visit editor displayed 添加菜品 below 本次照片; clicking added editable dish fields with a locked photo entry. Unsaved test draft was discarded, no visit was saved.

## Remaining verification limits

This is not a claim of exhaustive runtime acceptance of every Native rollback screen, every Browser route, cross-device daily allowance or a production server deployment. Those paths received code-level review / focused tests where applicable; this run's interactive acceptance used the QA Hybrid simulator. Roulette allowance is local per account/day, not server-enforced across devices. No production account subscription or cloud entitlement was changed.

## Design System Compliance

- Core UI: shared PremiumFeatureLabel / PremiumAccess and existing filter, rating and form controls; lock accessible labels; add-dish action retains 44-point minimum hit target.
- Food & Dining: existing renderer/assets and user photos preserved, no new art or asset substitution.
- Canonical templates: profile, analysis, filter sheet and visit editor hierarchy preserved; dish block remains immediately after visit photos.
- Duplicate components: Native rollback remains a legitimate separate consumer, not removed. Full runtime parity is not certified by this QA pass.
- No default SwiftUI visual replacement introduced; remaining gaps are the runtime coverage and device-local allowance limits noted above.
