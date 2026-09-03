# Restaurant Detail social rating reference closure

Date: 2026-09-04

## Root cause

Hybrid Restaurant Detail explicitly disabled the component's remote request, but the typed `restaurant.get` contract did not carry social rating aggregates. As a result, `RestaurantSocialStatsPanel` could only render honest empty states for 全部用户、好友评分、同味评分 even when the Rich Demo represented a populated social graph.

## Closed data path

- React renders adapter-owned `socialStats`; it does not infer relationships, ownership, or a second data model.
- Browser production resolves the existing official Restaurant stats endpoint.
- iOS production resolves the exact Global Restaurant identity from the current user's authorized Discovery cache projection.
- Rich Demo uses isolated DEBUG-only, deterministic, distinct, above-threshold group samples so the complete UI can be verified without claiming that fixture values are production records.
- A Restaurant with no qualifying aggregate remains `暂无数据`.

## Fixed Simulator evidence

- Device: iPhone 17 Pro, iOS 26.5
- UDID: `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`
- First proof: 青岚寿司 1 — 我的评分 8.3（3）、全部用户 8.6（40）、好友评分 9.2（12）、同味评分 9.0（16）
- Current Simulator page: 南山素食 3 — 我的评分 9.0（2）、全部用户 8.6（28）、好友评分 9.3（11）、同味评分 8.9（13）
- Screenshots: `restaurant-detail-all-rating-references-iphone17pro.png` and `restaurant-detail-all-rating-references-current-simulator.png`

## Verification

- Frontend tests: 62 files / 453 tests passed.
- iOS unit and integration tests: 66 suites / 649 tests passed.
- Focused Hybrid bridge suite: 9 tests passed, including exact Restaurant identity, current-account scope, 5-point-to-10-point projection, and owned/public detail parity.
- Manual fixed-Simulator rendering: passed; all four reference groups render concurrently with sample counts.
- Release purity: verified after formal staging; DEBUG fixture resources are excluded from Release.

An unrelated pre-existing UI-test assertion for the Roulette Dynamic Type touch target (`18 < 44`) was observed during an additional full UI-test run. It is outside this rating-reference change and is recorded rather than silently treated as a rating failure.
